# `std.crypto`

> Source: `/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/crypto.zig`  
> [← Back to Standard Library Index](README.md)

Cryptography.

## Types

### `SideChannelsMitigations`

Side-channels mitigations.

### Fields

- `none`
  No additional side-channel mitigations are applied.
  This is the fastest mode.
- `basic`
  The `basic` mode protects against most practical attacks, provided that the
  application or implements proper defenses against brute-force attacks.
  It offers a good balance between performance and security.
- `medium`
  The `medium` mode offers increased resilience against side-channel attacks,
  making most attacks unpractical even on shared/low latency environements.
  This is the default mode.
- `full`
  The `full` mode offers the highest level of protection against side-channel attacks.
  Note that this doesn't cover all possible attacks (especially power analysis or
  thread-local attacks such as cachebleed), and that the performance impact is significant.

## Namespaces

- **`aead`**: Authenticated Encryption with Associated Data
- **`auth`**: Authentication (MAC) functions.
- **`core`**: Core functions, that should rarely be used directly by applications.
- **`dh`**: Diffie-Hellman key exchange functions.
- **`kem`**: Key Encapsulation Mechanisms.
- **`ecc`**: Elliptic-curve arithmetic.
- **`hash`**: Hash functions.
- **`kdf`**: Key derivation functions.
- **`onetimeauth`**: MAC functions requiring single-use secret keys.
- **`pwhash`**: A password hashing function derives a uniform key from low-entropy input material such as passwords.
- **`sign`**: Digital signature functions.
- **`stream`**: Stream ciphers. These do not provide any kind of authentication.
- **`nacl`**: 

## Functions

### `secureZero`

```zig
pub fn secureZero(comptime T: type, s: []volatile T) void
```

Sets a slice to zeroes.
Prevents the store from being optimized out.

## Constants & Variables

- **`timing_safe`**: 
- **`ff`**: Finite-field arithmetic.
- **`codecs`**: Encoding and decoding
- **`errors`**: 
- **`tls`**: 
- **`Certificate`**: 
- **`default_side_channels_mitigations`**: 

