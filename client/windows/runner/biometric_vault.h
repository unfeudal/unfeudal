// SPDX-License-Identifier: Apache-2.0
#ifndef RUNNER_BIOMETRIC_VAULT_H_
#define RUNNER_BIOMETRIC_VAULT_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// Registers the fr.unfeudal/biometric channel: a 32-byte secret that Windows Hello releases.
void RegisterBiometricVault(flutter::BinaryMessenger* messenger, HWND window);

// Delivers a result posted back to the window thread; true when |message| was one.
bool HandleBiometricMessage(UINT message, LPARAM lparam);

#endif  // RUNNER_BIOMETRIC_VAULT_H_
