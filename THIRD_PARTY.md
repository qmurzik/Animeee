VLCKit and libVLC are used for native MPEG-DASH playback, through VLCKitSPM 3.6.0.
Copyright VideoLAN and contributors. LGPL 2.1; see Licenses/VLCKit-LGPL-2.1.txt.

Library source: https://code.videolan.org/videolan/VLCKit
SPM wrapper source and build scripts: https://github.com/tylerjonesio/vlckit-spm/tree/3.6.0
Distributed framework: https://github.com/tylerjonesio/vlckit-spm/releases/tag/3.6.0

This repository provides application source and Xcode project to rebuild/relink the application with a modified library. No DRM decryption or bypass is implemented. Manifests declaring ContentProtection are rejected by the DASH adapter.
