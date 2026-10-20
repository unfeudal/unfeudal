// SPDX-License-Identifier: Apache-2.0
#include "biometric_vault.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.h>
#include <winrt/Windows.Security.Cryptography.Core.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Storage.Streams.h>

#include <memory>
#include <thread>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;
using winrt::Windows::Security::Credentials::KeyCredentialCreationOption;
using winrt::Windows::Security::Credentials::KeyCredentialManager;
using winrt::Windows::Security::Credentials::KeyCredentialStatus;
using winrt::Windows::Security::Cryptography::BinaryStringEncoding;
using winrt::Windows::Security::Cryptography::CryptographicBuffer;
using winrt::Windows::Security::Cryptography::Core::HashAlgorithmNames;
using winrt::Windows::Security::Cryptography::Core::HashAlgorithmProvider;

constexpr UINT kResultMessage = WM_APP + 0x42;
constexpr wchar_t kCredentialName[] = L"fr.unfeudal.biometric";

HWND g_window = nullptr;
std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;

// A result computed on a worker thread; MethodResult is answered on the window thread.
struct Pending {
  std::unique_ptr<MethodResult<EncodableValue>> result;
  EncodableValue value;
};

void Reply(std::unique_ptr<MethodResult<EncodableValue>> result,
           EncodableValue value) {
  auto* pending = new Pending{std::move(result), std::move(value)};
  if (!PostMessage(g_window, kResultMessage, 0,
                   reinterpret_cast<LPARAM>(pending))) {
    delete pending;  // the window is gone: nobody waits for the answer
  }
}

EncodableValue Available() {
  return EncodableValue(KeyCredentialManager::IsSupportedAsync().get());
}

// The secret is the SHA-256 of the Hello key's signature of a fixed text: RSA PKCS#1 v1.5 signs
// deterministically, so the same key always yields the same secret. Null when cancelled or gone.
EncodableValue Secret(bool create) {
  auto retrieval =
      create ? KeyCredentialManager::RequestCreateAsync(
                   kCredentialName, KeyCredentialCreationOption::ReplaceExisting)
                   .get()
             : KeyCredentialManager::OpenAsync(kCredentialName).get();
  if (retrieval.Status() != KeyCredentialStatus::Success) {
    return EncodableValue();
  }
  auto data = CryptographicBuffer::ConvertStringToBinary(
      L"unfeudal/biometric/v1", BinaryStringEncoding::Utf8);
  auto signature = retrieval.Credential().RequestSignAsync(data).get();
  if (signature.Status() != KeyCredentialStatus::Success) {
    return EncodableValue();
  }
  auto hash = HashAlgorithmProvider::OpenAlgorithm(HashAlgorithmNames::Sha256())
                  .HashData(signature.Result());
  winrt::com_array<uint8_t> bytes;
  CryptographicBuffer::CopyToByteArray(hash, bytes);
  return EncodableValue(std::vector<uint8_t>(bytes.begin(), bytes.end()));
}

EncodableValue Delete() {
  KeyCredentialManager::DeleteAsync(kCredentialName).get();
  return EncodableValue();
}

// Hello calls block until the user answers the prompt: they run off the window thread.
template <typename Work>
void RunAsync(std::unique_ptr<MethodResult<EncodableValue>> result,
              EncodableValue fallback, Work work) {
  std::thread([result = std::move(result), fallback = std::move(fallback),
               work]() mutable {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    EncodableValue value;
    try {
      value = work();
    } catch (const winrt::hresult_error&) {
      value = fallback;  // no Hello, no credential, or the user closed the prompt
    }
    winrt::uninit_apartment();
    Reply(std::move(result), std::move(value));
  }).detach();
}

void HandleCall(const MethodCall<EncodableValue>& call,
                std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto& method = call.method_name();
  if (method == "available") {
    RunAsync(std::move(result), EncodableValue(false), Available);
  } else if (method == "secret") {
    bool create = false;
    if (const auto* args = std::get_if<EncodableMap>(call.arguments())) {
      auto found = args->find(EncodableValue("create"));
      if (found != args->end()) {
        if (const auto* value = std::get_if<bool>(&found->second)) {
          create = *value;
        }
      }
    }
    // the "reason" argument is not used: Windows Hello shows its own prompt text
    RunAsync(std::move(result), EncodableValue(),
             [create] { return Secret(create); });
  } else if (method == "delete") {
    RunAsync(std::move(result), EncodableValue(), Delete);
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void RegisterBiometricVault(flutter::BinaryMessenger* messenger, HWND window) {
  g_window = window;
  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "fr.unfeudal/biometric",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(HandleCall);
}

bool HandleBiometricMessage(UINT message, LPARAM lparam) {
  if (message != kResultMessage) {
    return false;
  }
  std::unique_ptr<Pending> pending(reinterpret_cast<Pending*>(lparam));
  pending->result->Success(pending->value);
  return true;
}
