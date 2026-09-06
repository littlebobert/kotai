# Vendored Hummingbird 2.26.0

This directory contains the minimum Hummingbird 2.26.0 package used by Kotai. It is vendored solely to preserve Xcode 27 package-framework linkage while upstream package metadata is incompatible with that toolchain.

The source is otherwise unchanged. The local manifest has three direct dependency corrections required for reliable Xcode 27 linking:

- `HummingbirdCore` directly declares `NIOHTTP1`.
- `Hummingbird` directly declares `ServiceContextModule`.
- `Hummingbird` directly declares `SystemPackage`.

Only the `Hummingbird`, `HummingbirdCore`, and `HummingbirdTesting` products and source targets are retained. Upstream copyright and attribution terms remain in `LICENSE.txt` and `NOTICE.txt`.
