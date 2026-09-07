{
  lib,
  stdenv,
  fetchFromGitHub,
  buildGoModule,
  cmake,
  ninja,
  pkg-config,
  makeWrapper,
  qt6,
  boost,
  miniaudio,
  libnl,
  libcap_ng,
  nftables,
  iptables,
  iproute2,
  procps,
  spdlog,
  fmt,
  c-ares,
  openssl_4_0,
  curl,
  tl-expected,
  range-v3,
  nlohmann_json,
  acl,
  autoreconfHook,
  lzo,
  lz4,
  python3Packages,
  cmakerc,
  gtest,
  rapidjson,
  e2fsprogs,
  util-linux,
  kmod,
  iw,
  systemd,
}:

let
  # Upstream Windscribe vcpkg port registry (contains custom crypto/tunnel patches)
  ws-vcpkg-registry = fetchFromGitHub {
    owner = "Windscribe";
    repo = "ws-vcpkg-registry";
    rev = "ef9b1277cc637891ca2b17638e21aa5d71f8f379";
    hash = "sha256-ZjXPjt1Hv8lXB39v6c50OAfnosKUdpHuzgnbt7d0SUE=";
  };

  # 1. Skyr URL
  skyr-url = stdenv.mkDerivation {
    pname = "skyr-url";
    version = "1.13.0";
    src = fetchFromGitHub {
      owner = "cpp-netlib";
      repo = "url";
      rev = "v1.13.0";
      hash = "sha256-f+WcXdvsIGfXUIIK039DP3GS/BzOMbx9lH0G2ZM9NOg=";
    };
    nativeBuildInputs = [ cmake ];
    propagatedBuildInputs = [
      nlohmann_json
      range-v3
      tl-expected
    ];
    cmakeFlags = [
      "-Dskyr_BUILD_TESTS=OFF"
      "-Dskyr_BUILD_DOCS=OFF"
      "-Dskyr_BUILD_EXAMPLES=OFF"
      "-Dskyr_WARNINGS_AS_ERRORS=OFF"
      "-Dskyr_ENABLE_FILESYSTEM_FUNCTIONS=OFF"
    ];
  };

  # 2. OpenSSL with TLS Padding Support
  openssl-custom = openssl_4_0.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      "${ws-vcpkg-registry}/ports/openssl/tls-padding.patch"
    ];
    doCheck = false;
  });

  # 3. cURL with Super-Large Padding & Legacy EC Point Formats
  curl-custom = (curl.override { openssl = openssl-custom; }).overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      "${ws-vcpkg-registry}/ports/curl/super-large-padding-extension.patch"
      "${ws-vcpkg-registry}/ports/curl/Export-SSL_OP_LEGACY_EC_POINT_FORMATS-OpenSSL-option.patch"
    ];
    doCheck = false;
  });

  # 4. Inlined Header Dependencies for wsnet
  cppBase64Src = fetchFromGitHub {
    owner = "ReneNyffenegger";
    repo = "cpp-base64";
    rev = "951de609dbe27ce8864dfe47323c4ade96bee86e";
    hash = "sha256-rivCuVLJchAINKSQ9/7UWz5ibPZ6jOqovCvOE+ZtTvo=";
  };
  cpp-base64 = stdenv.mkDerivation {
    name = "cpp-base64";
    buildCommand = ''
      mkdir -p $out/include/cpp-base64
      cp ${cppBase64Src}/* $out/include/cpp-base64/
    '';
  };

  advobfuscatorSrc = fetchFromGitHub {
    owner = "andrivet";
    repo = "ADVobfuscator";
    rev = "1852a0eb75b03ab3139af7f938dfb617c292c600";
    hash = "sha256-qleFYWPmCYHHtBO3Op3e8T6fxmC/3KwpatcQ8keiiz8=";
  };

  # 5. wsnet Library
  wsnet = stdenv.mkDerivation {
    pname = "wsnet";
    version = "1.5.32";
    src = fetchFromGitHub {
      owner = "Windscribe";
      repo = "wsnet";
      rev = "1.5.32";
      hash = "sha256-W4qArEGc5Vk9HXoZlZxD8JEl9NRadJzZsKBYf5zZyOI=";
    };
    nativeBuildInputs = [
      cmake
      pkg-config
    ];
    buildInputs = [
      c-ares
      curl-custom
      openssl-custom
      spdlog
      rapidjson
      skyr-url
      boost
      cmakerc
      gtest
    ];
    postPatch = ''
      substituteInPlace CMakeLists.txt \
        --replace-fail "find_package(CURL CONFIG REQUIRED)" "find_package(CURL REQUIRED)"
    '';
    cmakeFlags = [
      "-DIS_BUILD_TESTS=OFF"
      "-DCPP_BASE64_INCLUDE_DIRS=${cpp-base64}/include"
      "-DADVOBFUSCATOR_INCLUDE_DIRS=${advobfuscatorSrc}"
    ];
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib $out/include
      install -m 755 libwsnet.so $out/lib/
      cp -r $src/include/* $out/include/
      cp -r $src/src $out/include/wsnet_internal
      runHook postInstall
    '';
  };

  # 6. Control D DNS Forwarding Proxy (ctrld)
  windscribectrld = buildGoModule rec {
    pname = "windscribectrld";
    version = "1.5.0";
    src = fetchFromGitHub {
      owner = "Control-D-Inc";
      repo = "ctrld";
      rev = "v${version}";
      hash = "sha256-KrkEI07wfddDGmor2VT3I5gGmeZX75UGLZl++a6sE+c=";
    };
    vendorHash = "sha256-rsRlInNk6/C9DzJLbCoQSbV1exGfstbTxE8qitKmZ0c=";
    subPackages = [ "cmd/ctrld" ];
    ldflags = [
      "-s"
      "-w"
      "-X main.version=v${version}"
    ];
    postInstall = ''
      mv $out/bin/ctrld $out/bin/windscribectrld
    '';
  };

  # 7. Amnezia WireGuard (amneziawg-go)
  windscribeamneziawg = buildGoModule {
    pname = "windscribeamneziawg";
    version = "0.2.16";
    src = fetchFromGitHub {
      owner = "amnezia-vpn";
      repo = "amneziawg-go";
      rev = "v0.2.16";
      hash = "sha256-JGmWMPVgereSZmdHUHC7ZqWCwUNfxfj3xBf/XDDHhpo=";
    };
    proxyVendor = true;
    vendorHash = "sha256-f3ZwJZdU9BmY/+PGeV4/xqbceZJfuNqmZsJ2VgAQqyI=";
    postInstall = ''
      mv $out/bin/amneziawg-go $out/bin/windscribeamneziawg
    '';
  };

  # 8. wstunnel
  windscribewstunnel = buildGoModule {
    pname = "windscribewstunnel";
    version = "1.0.7";
    src = fetchFromGitHub {
      owner = "Windscribe";
      repo = "wstunnel";
      rev = "e6c325eed099e746ee98f80de7b827e942416d20";
      hash = "sha256-m1vy6yQKE4PSAcYRvHIz0f3Mc08NB9OdZwhB0zk0LjA=";
    };
    proxyVendor = true;
    vendorHash = "sha256-EChb+QiY4A1/XUnjCx9gAdrsNaSwiJ1r55gY/W74F5s=";
    subPackages = [ "." ];
    postInstall = ''
      mv $out/bin/wstunnel $out/bin/windscribewstunnel
    '';
  };

  # 9. OpenVPN 2.7.5 with DCO & Anti-Censorship Patches
  windscribeopenvpn = stdenv.mkDerivation {
    pname = "windscribeopenvpn";
    version = "2.7.5";
    src = fetchFromGitHub {
      owner = "OpenVPN";
      repo = "openvpn";
      rev = "b25bb2a8bda814edab39b4246d4e296330a7a29e";
      hash = "sha256-oyKidDw+3PRmHezyftfYXqe8pIwF0Bnr4ue1Alq5zKc=";
    };
    nativeBuildInputs = [
      autoreconfHook
      pkg-config
      python3Packages.docutils
    ];
    buildInputs = [
      openssl-custom
      lzo
      lz4
      libcap_ng
      libnl
    ];
    patches = [
      "${ws-vcpkg-registry}/ports/openvpn/anti-censorship.patch"
      "${ws-vcpkg-registry}/ports/openvpn/0002-Anti-censorship-add-support-for-Amnezia-s-Jc-Jmin-Jm.patch"
      "${ws-vcpkg-registry}/ports/openvpn/0003-Anti-censorship-introduce-junk-first-option-Jc-befor.patch"
    ];
    configureFlags = [
      "--with-crypto-library=openssl"
      "--disable-plugin-auth-pam"
      "--disable-plugin-down-root"
      "--enable-dco"
    ];
    installTargets = [ "install-exec" ];
    postInstall = ''
      mkdir -p $out/bin
      mv $out/sbin/openvpn $out/bin/windscribeopenvpn 2>/dev/null || mv $out/bin/openvpn $out/bin/windscribeopenvpn
    '';
  };

in
stdenv.mkDerivation (finalAttrs: {
  pname = "windscribe";
  version = "2.24.12";

  src = fetchFromGitHub {
    owner = "Windscribe";
    repo = "Desktop-App";
    rev = "v${finalAttrs.version}";
    hash = "sha256-RiSpysVSrzhWtTgkQmspQ/Hj2cFQLIyjEtfoT7YhM1Q=";
  };

  patches = [
    ./patches/nixos.patch
  ];

  postPatch = ''
    # 1. Fix systemd-resolved drop-in directory
    substituteInPlace src/installer/windscribe/linux/opt/windscribe/scripts/update-systemd-resolved \
      --replace-fail '/usr/local/lib/systemd/resolved.conf.d' '/etc/systemd/resolved.conf.d'

    # 2. Prevent CLI binaries from clearing Qt plugin search paths
    substituteInPlace src/windscribe-cli/main.cpp \
      --replace-fail 'QCoreApplication::setLibraryPaths(QStringList());' '// QCoreApplication::setLibraryPaths disabled for Nix'
    substituteInPlace src/client/frontend/cli/main.cpp \
      --replace-fail 'QCoreApplication::setLibraryPaths(pluginsPath);' '// QCoreApplication::setLibraryPaths disabled for Nix'

    # 3. Fix update signature verification tool lookup
    substituteInPlace src/helper/linux/installer_verifier.cpp \
      --replace-fail 'constexpr const char *kGpgvPath = "/usr/bin/gpgv";' 'constexpr const char *kGpgvPath = "gpgv";'

    # 4. Fallback XDG application paths for Split Tunneling on NixOS
    substituteInPlace src/client/client-common/utils/linuxutils.cpp \
      --replace-fail '"/usr/local/share/:/usr/share/"' '"/run/current-system/sw/share:/usr/share/"'
  '';

  strictDeps = true;
  __structuredAttrs = true;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    qt6.wrapQtAppsHook
    makeWrapper
    python3Packages.python
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtsvg
    qt6.qtwayland
    qt6.qttools
    boost
    miniaudio.dev
    libnl
    libcap_ng
    nftables
    spdlog
    fmt
    c-ares
    openssl-custom
    tl-expected
    range-v3
    nlohmann_json
    acl
    skyr-url
    wsnet
  ];

  NIX_CFLAGS_COMPILE = "-isystem ${miniaudio.dev}/include/miniaudio";

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DINTEGRATION_TYPE=gui"
    "-DBUILD_APP=ON"
    "-DBUILD_INSTALLER=OFF"
    "-DBUILD_DEB=OFF"
    "-DBUILD_RPM=OFF"
    "-DBUILD_RPM_OPENSUSE=OFF"
    "-DBUILD_TESTS=OFF"
    "-DWSNET_DIR=${wsnet}"
    "-DCMAKE_PREFIX_PATH=${skyr-url};${wsnet}"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt/windscribe/lib $out/bin $out/share/applications $out/share/icons/hicolor $out/etc/windscribe/autostart

    # 1. Main Binaries & Shared Libraries
    install -m 755 src/client/Windscribe $out/opt/windscribe/Windscribe
    install -m 755 src/windscribe-cli/windscribe-cli $out/opt/windscribe/windscribe-cli
    install -m 755 src/helper/linux/helper $out/opt/windscribe/helper
    ln -s helper $out/opt/windscribe/windscribe-helper
    install -m 755 ${wsnet}/lib/libwsnet.so $out/opt/windscribe/lib/libwsnet.so

    # 2. Bundled Helper Executables
    install -m 755 ${windscribectrld}/bin/windscribectrld $out/opt/windscribe/windscribectrld
    install -m 755 ${windscribeamneziawg}/bin/windscribeamneziawg $out/opt/windscribe/windscribeamneziawg
    install -m 755 ${windscribewstunnel}/bin/windscribewstunnel $out/opt/windscribe/windscribewstunnel
    install -m 755 ${windscribeopenvpn}/bin/windscribeopenvpn $out/opt/windscribe/windscribeopenvpn

    # 3. Scripts
    mkdir -p $out/opt/windscribe/scripts
    cp -r ../src/installer/windscribe/linux/opt/windscribe/scripts/* $out/opt/windscribe/scripts/
    chmod +x $out/opt/windscribe/scripts/*
    patchShebangs $out/opt/windscribe/scripts/

    # 4. Desktop Entries & Icons
    install -m 644 ../src/installer/gui/linux/overlay/usr/share/applications/windscribe.desktop $out/share/applications/windscribe.desktop
    substituteInPlace $out/share/applications/windscribe.desktop \
      --replace-fail "Exec=/opt/windscribe/Windscribe" "Exec=windscribe"

    install -m 644 ../src/installer/gui/linux/overlay/etc/windscribe/autostart/windscribe.desktop $out/etc/windscribe/autostart/windscribe.desktop
    substituteInPlace $out/etc/windscribe/autostart/windscribe.desktop \
      --replace-fail "Exec=/opt/windscribe/Windscribe" "Exec=windscribe"

    for size in 16x16 24x24 32x32 48x48 64x64 128x128 256x256; do
      iconDir="$out/share/icons/hicolor/$size/apps"
      mkdir -p "$iconDir"
      if [ -f "../src/installer/gui/linux/png_icons/$size/windscribe.png" ]; then
        install -m 644 "../src/installer/gui/linux/png_icons/$size/windscribe.png" "$iconDir/Windscribe.png"
        ln -sf Windscribe.png "$iconDir/windscribe.png"
      fi
    done

    cat > $out/opt/windscribe/scripts/install-update << 'EOF'
    #!/bin/bash
    echo "Windscribe on NixOS is managed declaratively."
    echo "Update your flake inputs and run: rebuild"
    exit 0
    EOF
    chmod +x $out/opt/windscribe/scripts/install-update

    # 5. CLI & GUI Wrappers
    mkdir -p $out/bin
    ln -sf ../opt/windscribe/windscribe-cli $out/bin/windscribe-cli
    ln -sf ../opt/windscribe/helper $out/bin/windscribe-helper
    ln -sf ../opt/windscribe/Windscribe $out/bin/windscribe

    runHook postInstall
  '';

  preFixup = ''
    qtWrapperArgs+=(
      --prefix PATH : ${
        lib.makeBinPath [
          iproute2
          nftables
          iptables
          procps
          e2fsprogs
          util-linux
          kmod
          iw
          systemd
        ]
      }
    )
  '';

  postFixup = ''
    wrapQtApp "$out/opt/windscribe/Windscribe"
    wrapQtApp "$out/opt/windscribe/windscribe-cli"
  '';

  meta = {
    description = "Windscribe Desktop VPN Client and Helper Suite";
    homepage = "https://windscribe.com";
    license = lib.licenses.gpl2Only;
    maintainers = with lib.maintainers; [ aliheidary1381 ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ]; # To future contributors: darwin is possible, but needs more patches. You're on your own.
    mainProgram = "windscribe";
  };
})
