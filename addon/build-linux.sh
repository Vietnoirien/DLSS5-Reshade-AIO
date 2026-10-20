#!/usr/bin/env bash
# Cross-builds the 64-bit addon on Linux with clang-cl + lld-link against an
# xwin-splatted MSVC CRT/Windows SDK. Mirrors the cl.exe steps of build.bat
# (the Vulkan fallback layer is not built here).
#
#   XWIN         xwin splat output (default: ~/.xwin)
#   NGX_INCLUDE  directory holding nvsdk_ngx*.h (default: external/ngx)
#   LLVM_SUFFIX  suffix of the clang-cl/lld-link binaries (default: -21)
set -euo pipefail
cd "$(dirname "$0")"

XWIN="${XWIN:-$HOME/.xwin}"
FEEDER_ROOT="../external/DLSS5-Feeder"
NGX_INCLUDE="${NGX_INCLUDE:-$FEEDER_ROOT/external/ngx}"
LLVM_SUFFIX="${LLVM_SUFFIX:--21}"
CLANG_CL="clang-cl$LLVM_SUFFIX"
LLD_LINK="lld-link$LLVM_SUFFIX"

mkdir -p build/obj build/shim

# The addon includes nvsdk_ngx_defs_dlssg.h but uses none of its declarations;
# provide an empty stand-in when the NGX directory lacks it.
if [[ ! -f "$NGX_INCLUDE/nvsdk_ngx_defs_dlssg.h" ]]; then
    printf '#pragma once\n' > build/shim/nvsdk_ngx_defs_dlssg.h
fi

SYS_INCLUDES=(
    /imsvc"$XWIN/crt/include"
    /imsvc"$XWIN/sdk/include/ucrt"
    /imsvc"$XWIN/sdk/include/um"
    /imsvc"$XWIN/sdk/include/shared"
    /imsvc"$XWIN/sdk/include/winrt"
)
LIB_PATHS=(
    /libpath:"$XWIN/crt/lib/x86_64"
    /libpath:"$XWIN/sdk/lib/um/x86_64"
    /libpath:"$XWIN/sdk/lib/ucrt/x86_64"
)
COMMON=(--target=x86_64-pc-windows-msvc -fuse-ld=lld /nologo /EHsc /O2 /MD /W3
    -Wno-unused-command-line-argument -Wno-microsoft-cast "${SYS_INCLUDES[@]}")

"$CLANG_CL" "${COMMON[@]}" /std:c++17 /c src/nvngx-bridge.cpp /Fobuild/obj/nvngx-bridge.obj
"$LLD_LINK" /nologo /dll "${LIB_PATHS[@]}" build/obj/nvngx-bridge.obj d3d12.lib \
    /out:build/nvngx.dll /implib:build/nvngx.lib

ADDON_INCLUDES=(
    /I"$NGX_INCLUDE" /Ibuild/shim
    /I"$FEEDER_ROOT/external/reshade/include"
    /I"$FEEDER_ROOT/external/imgui"
    /I"$FEEDER_ROOT/external/vulkan"
    /I"$FEEDER_ROOT/external/minhook/include"
    /Iinclude
)
OBJS=()
for src in src/nr-standalone.cpp src/nvof-motion-provider.cpp; do
    obj="build/obj/$(basename "${src%.*}").obj"
    "$CLANG_CL" "${COMMON[@]}" /std:c++20 "${ADDON_INCLUDES[@]}" /c "$src" /Fo"$obj"
    OBJS+=("$obj")
done
for src in buffer.c hook.c trampoline.c hde/hde64.c; do
    obj="build/obj/minhook-$(basename "${src%.*}").obj"
    "$CLANG_CL" "${COMMON[@]}" /c "$FEEDER_ROOT/external/minhook/src/$src" /Fo"$obj"
    OBJS+=("$obj")
done
"$LLD_LINK" /nologo /dll "${LIB_PATHS[@]}" "${OBJS[@]}" \
    kernel32.lib user32.lib d3d9.lib d3d11.lib d3d12.lib dxgi.lib d3dcompiler.lib dcomp.lib \
    /out:build/standalone-dlssnr.addon64 /implib:build/standalone-dlssnr.lib

cp -f shaders/DLSS5_AIO_Feed.fx shaders/StandaloneBoundary.fx build/
echo "Standalone addon built in $PWD/build"
