#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Automation script for Building Kernels on Github Actions

# Download latest Neutron clang from their repos.
mkdir -p Neutron/
curl -s https://api.github.com/repos/Neutron-Toolchains/clang-build-catalogue/releases/latest \
| grep "browser_download_url.*tar.zst" \
| cut -d : -f 2,3 \
| tr -d \" \
| wget --output-document=Neutron.tar.zst -qi -

tar -xf Neutron.tar.zst -C Neutron/ || exit 1

# Clone dependant repositories
# git clone --depth 1 -b gcc-master https://github.com/mvaisakh/gcc-arm64.git gcc-arm64
# git clone --depth 1 -b gcc-master https://github.com/mvaisakh/gcc-arm.git gcc-arm
git clone --depth 1 -b surya https://github.com/taalojarvi/AnyKernel3 || exit 1
git clone --depth 1 https://github.com/Stratosphere-Kernel/Stratosphere-Canaries || exit 1

# Workaround for safe.directory permission fix
git config --global safe.directory "$GITHUB_WORKSPACE"
git config --global safe.directory /github/workspace
git config --global --add safe.directory /__w/android_kernel_xiaomi_surya/android_kernel_xiaomi_surya

# Export Environment Variables. 
export DATE=$(date +"%d-%m-%Y-%I-%M")
export PATH="$(pwd)/Neutron/bin:$PATH"
# export PATH="$TC_DIR/bin:$HOME/gcc-arm/bin${PATH}"
export CLANG_TRIPLE=aarch64-linux-gnu-
export ARCH=arm64
# export CROSS_COMPILE=$(pwd)/gcc-arm64/bin/aarch64-elf-
# export CROSS_COMPILE_ARM32=$(pwd)/gcc-arm/bin/arm-eabi-
export CROSS_COMPILE=aarch64-linux-gnu-
# export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
# export CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export LD_LIBRARY_PATH=$TC_DIR/lib
export KBUILD_BUILD_USER="taalojarvi"
export KBUILD_BUILD_HOST="github.com"
export USE_HOST_LEX=yes
export KERNEL_IMG=output/arch/arm64/boot/Image
export KERNEL_DTBO=output/arch/arm64/boot/dtbo.img
export KERNEL_DTB=output/arch/arm64/boot/dts/qcom/sdmmagpie.dtb
export DEFCONFIG=surya_defconfig
export ANYKERNEL_DIR=$(pwd)/AnyKernel3/
export BUILD_NUMBER=$((GITHUB_RUN_NUMBER + 424))
export PATH="/usr/lib/ccache:/usr/local/opt/ccache/libexec:$PATH"

# Telegram API Stuff
BUILD_START=$(date +"%s")
KBUILD_COMPILER_STRING=$("$TC_DIR"/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
BOT_MSG_URL="https://api.telegram.org/bot$token/sendMessage"
BOT_BUILD_URL="https://api.telegram.org/bot$token/sendDocument"
CHATID=-1001719821334
COMMIT_HEAD=$(git log --oneline -1)
TERM=xterm
if [ "$(cat /sys/devices/system/cpu/smt/active)" = "1" ]; then
		export THREADS=$(($(nproc --all) * 2))
	else
		export THREADS=$(nproc --all)
	fi
##---------------------------------------------------------##

tg_post_msg() {
	curl -s -X POST "$BOT_MSG_URL" -d chat_id="$CHATID" \
	-d "disable_web_page_preview=true" \
	-d "parse_mode=html" \
	-d text="$1"

}

##----------------------------------------------------------------##

tg_post_build() {
	#Post MD5Checksum alongwith for easeness
	MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)

	#Show the Checksum alongwith caption
	curl --progress-bar -F document=@"$1" "$BOT_BUILD_URL" \
	-F chat_id="$CHATID"  \
	-F "disable_web_page_preview=true" \
	-F "parse_mode=Markdown" \
	-F caption="$2 | *MD5 Checksum : *\`$MD5CHECK\`"
}

##----------------------------------------------------------##

# Create Release Notes [Deprecated] 
function releasenotes(){
touch releasenotes.md
echo -e "This is an Automated Build of Stratosphere Kernel. Flash at your own risk!" > releasenotes.md
echo -e >> releasenotes.md
echo -e "Build Information" >> releasenotes.md
echo -e >> releasenotes.md
echo -e "Build Server Name: "$RUNNER_NAME >> releasenotes.md
echo -e "Build ID: "$GITHUB_RUN_ID >> releasenotes.md
echo -e "Build URL: "$GITHUB_SERVER_URL >> releasenotes.md
echo -e >> releasenotes.md
echo -e "Last 5 Commits before Build:-" >> releasenotes.md
git log --decorate=auto --pretty=reference --graph -n 10 >> releasenotes.md
cp releasenotes.md $(pwd)/Stratosphere-Canaries/
}

# Make defconfig
# make $DEFCONFIG LD=aarch64-elf-ld.lld O=output/
make $DEFCONFIG -j$THREADS CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip O=output/

# Make Kernel
tg_post_msg "<b> Build Started on Github Actions</b>%0A<b>Build Number: </b><code>"$BUILD_NUMBER"</code>%0A<b>Date : </b><code>$(TZ=Etc/UTC date)</code>%0A<b>Top Commit : </b><code>$COMMIT_HEAD</code>%0A"
# make -j$THREADS LD=ld.lld O=output/
make -j$THREADS CC='ccache clang -Qunused-arguments -fcolor-diagnostics' LLVM=1 LD=ld.lld LLVM_IAS=1 AS=llvm-as AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip O=output/

# Check if Image.gz-dtb exists. If not, stop executing.
if ! [ -a $KERNEL_IMG ];
  then
    echo "An error has occured during compilation. Please check your code."
    tg_post_msg "<b>An error has occured during compilation. Build has failed</b>%0A"
    exit 1
  fi 

# Make Flashable Zip
cp "$KERNEL_IMG" "$ANYKERNEL_DIR"
cp "$KERNEL_DTB" "$ANYKERNEL_DIR"/dtb 
cp "$KERNEL_DTBO" "$ANYKERNEL_DIR" 
cd AnyKernel3
# Add a fortune to the banner
if [ -x "$(command -v fortune)" ]; then
	printf "\n" >> banner
	fortune -n "$BUILD_NUMBER" >> banner
fi
zip -r9 UPDATE-AnyKernel2.zip * -x README.md LICENSE UPDATE-AnyKernel2.zip zipsigner.jar
cp UPDATE-AnyKernel2.zip package.zip 
curl -sLo zipsigner-3.0.jar https://github.com/Magisk-Modules-Repo/zipsigner/raw/master/bin/zipsigner-3.0-dexed.jar
java -jar zipsigner-3.0.jar UPDATE-AnyKernel2.zip Stratosphere-$BUILD_NUMBER.zip
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
tg_post_build "Stratosphere-$BUILD_NUMBER.zip" "Build took : $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)"


# Upload Flashable zip to tmp.ninja and uguu.se
# curl -i -F files[]=@Stratosphere-"$BUILD_NUMBER".zip https://uguu.se/upload.php
# curl -i -F files[]=@Stratosphere-"$BUILD_NUMBER".zip https://tmp.ninja/upload.php?output=text

cp Stratosphere-"$BUILD_NUMBER".zip ../Stratosphere-Canaries/
cd ../Stratosphere-Canaries/

# Upload Flashable Zip to GitHub Releases <3
# gh release create earlyaccess-$DATE "Stratosphere-""$BUILD_NUMBER"".zip" -F releasenotes.md -p -t "Stratosphere Kernel: Automated Build" || echo "gh-cli encountered an unexpected error"
