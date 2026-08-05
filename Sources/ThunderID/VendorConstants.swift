// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// Constants for vendor-specific configuration.
///
/// By default, the vendor is inferred as ThunderID.
public enum VendorConstants {
    /// The prefix used for vendor-specific storage identifiers (e.g. Keychain service name), or other
    /// runtime keys/names.
    public static let vendorPrefix: String = "thunderid"
}
