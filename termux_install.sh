#!/data/data/com.termux/files/usr/bin/bash
# سكربت إعداد Dex2c على Termux مع Android SDK/NDK و apktool
# نسخة مُصحَّحة مع كشف ديناميكي للمسارات والإصدارات
set -euo pipefail

# ================== فحص بيئة Termux ==================
if ! command -v termux-setup-storage >/dev/null 2>&1; then
  echo "This script can be executed only on Termux"
  exit 1
fi
termux-setup-storage || true

# ================== ألوان الطرفية ==================
green="$(tput setaf 2)"; red="$(tput setaf 1)"
yellow="$(tput setaf 3)"; blue="$(tput setaf 4)"
note="$(tput setaf 6)"; nocolor="$(tput sgr0)"

echo "${green}━━━ تحديث الحزم ━━━${nocolor}"
pkg update -y
pkg upgrade -y

echo "${green}━━━ تثبيت المتطلبات الأساسية ━━━${nocolor}"
pkg install -y ncurses-utils python git cmake rust clang make wget zlib libxml2 libxslt pkg-config libjpeg-turbo binutils openssl openjdk-17

# ================== حزم بايثون ==================
echo "${green}━━━ Python packages ━━━${nocolor}"
export LDFLAGS="-L${PREFIX}/lib/"
export CFLAGS="-I${PREFIX}/include/"
python -m pip install --upgrade pip wheel pillow
python -m pip install cython setuptools
CFLAGS="-Wno-error=incompatible-function-pointer-types -O0" python -m pip install lxml
python -m pip install cryptography

# ================== Android SDK Tools ==================
echo "${green}━━━ تثبيت Android SDK Tools ━━━${nocolor}"
cd "$HOME"
if [ -d "android-sdk" ]; then
  echo "${yellow}SDK tools موجودة مسبقًا. تخطّي.${nocolor}"
else
  rm -rf androidide-tools
  git clone https://github.com/AndroidIDEOfficial/androidide-tools
  cd androidide-tools/scripts
  ./idesetup -c
  cd "$HOME"
fi
echo "${yellow}Android SDK Tools تم تثبيتها.${nocolor}"

# ================== محاولة اكتشاف مجلد SDK ==================
SDK_HOME=""
SDK_CANDIDATES=("$HOME/android-sdk" "$HOME/.androidide" "$HOME/AndroidIDE" "$HOME/Android/Sdk")
for d in "${SDK_CANDIDATES[@]}"; do
  if [ -d "$d" ]; then
    SDK_HOME="$d"
    break
  fi
done
if [ -z "$SDK_HOME" ]; then
  echo "${red}تعذّر تحديد مسار Android SDK تلقائيًا.${nocolor}"
  echo "الرجاء تثبيت SDK عبر androidide-tools أو حدّد المسار يدويًا."
  exit 1
fi
echo "${blue}SDK_HOME = $SDK_HOME${nocolor}"

# ================== NDK (تنزيل/تثبيت) ==================
echo "${green}━━━ تثبيت Android NDK ━━━${nocolor}"
cd "$HOME"
if [ ! -f "ndk-install.sh" ]; then
  pkg install -y wget
  wget -q https://github.com/MrIkso/AndroidIDE-NDK/raw/main/ndk-install.sh -O ndk-install.sh
fi
chmod +x ndk-install.sh
# تنبيه: هذا سكربت خارجي؛ استخدمه على مسؤوليتك
bash ndk-install.sh

# ================== كشف ديناميكي لإصدار الـ NDK ==================
NDK_DIR=""
if [ -d "$SDK_HOME/ndk" ] && ls -1 "$SDK_HOME/ndk" | grep -q .; then
  # خُذ أول مجلد (أحدث عادةً عند الفرز)
  NDK_DIR="$(ls -d "$SDK_HOME/ndk"/* | sort -Vr | head -n1 || true)"
fi
if [ -z "$NDK_DIR" ]; then
  echo "${red}لم يتم العثور على NDK تحت: $SDK_HOME/ndk${nocolor}"
  echo "تأكد أن التنزيل تم بنجاح وأن sdkmanager والرخص بحالة مقبولة."
  exit 1
fi
ndk_version="$(basename "$NDK_DIR")"
echo "${yellow}تم العثور على NDK: ${ndk_version}${nocolor}"

# ================== قبول الرخص (اختياري لكنه مفيد) ==================
if [ -x "$SDK_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  yes | "$SDK_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null 2>&1 || true
fi

# ================== apktool ==================
echo "${green}━━━ إعداد apktool ━━━${nocolor}"
if [ -f "$PREFIX/bin/apktool.jar" ]; then
  echo "${blue}apktool موجود مسبقًا.${nocolor}"
else
  wget -q https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar -O "$PREFIX/bin/apktool.jar"
  chmod +r "$PREFIX/bin/apktool.jar"
  wget -q https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool -O "$PREFIX/bin/apktool"
  chmod +x "$PREFIX/bin/apktool"
fi

# ================== Dex2c ==================
echo "${green}━━━ تثبيت Dex2c ━━━${nocolor}"
cd "$HOME"
if [ -d "Dex2c" ]; then
  cd Dex2c
else
  git clone https://github.com/TechnoIndian/Dex2c
  cd Dex2c
fi

mkdir -p "$HOME/Dex2c/tools"
cp -f "$PREFIX/bin/apktool.jar" "$HOME/Dex2c/tools/apktool.jar"

python -m pip install -U -r requirements.txt

# ================== ضبط PATH والمتغيرات ==================
echo "${green}━━━ ضبط متغيرات البيئة ━━━${nocolor}"
# اختر ملف التهيئة المناسب
shell_rc=""
if [ -f "$HOME/.bashrc" ]; then
  shell_rc="$HOME/.bashrc"
elif [ -f "$HOME/.zshrc" ]; then
  shell_rc="$HOME/.zshrc"
else
  shell_rc="$PREFIX/etc/bash.bashrc"
fi

BUILD_TOOLS_DIR="$(ls -d "$SDK_HOME/build-tools"/* 2>/dev/null | sort -Vr | head -n1 || true)"

{
  echo ""
  echo "# ====== Android SDK/NDK (أُضيفت بواسطة setup_dex2c.sh) ======"
  echo "export ANDROID_HOME=\"$SDK_HOME\""
  echo "export ANDROID_NDK_ROOT=\"$SDK_HOME/ndk/$ndk_version\""
  echo "export PATH=\"\$PATH:$SDK_HOME/cmdline-tools/latest/bin\""
  echo "export PATH=\"\$PATH:$SDK_HOME/platform-tools\""
  [ -n "$BUILD_TOOLS_DIR" ] && echo "export PATH=\"\$PATH:$BUILD_TOOLS_DIR\""
  echo "export PATH=\"\$PATH:\$ANDROID_NDK_ROOT\""
} >> "$shell_rc"

# ================== ملف إعداد Dex2c ==================
cat > "$HOME/Dex2c/dcc.cfg" <<EOF
{
  "apktool": "tools/apktool.jar",
  "ndk_dir": "$SDK_HOME/ndk/$ndk_version",
  "signature": {
    "keystore_path": "keystore/debug.keystore",
    "alias": "androiddebugkey",
    "keystore_pass": "android",
    "store_pass": "android",
    "v1_enabled": true,
    "v2_enabled": true,
    "v3_enabled": true
  }
}
EOF

# ================== ختام ==================
echo
echo "${green}============================${nocolor}"
echo "تم إعداد Dex2c و Android SDK/NDK و apktool."
echo "لتفعيل PATH الآن، نفّذ:"
echo "source \"$shell_rc\""
echo
echo "تأكد من وجود build-tools و platform-tools عبر sdkmanager إذا لزم:"
echo "\"$SDK_HOME/cmdline-tools/latest/bin/sdkmanager\" --list | head"
echo
echo "لو ما عندك debug.keystore، أنشئه (من داخل مجلد Dex2c):"
echo "mkdir -p keystore && keytool -genkey -v \\"
echo "  -keystore keystore/debug.keystore -storepass android -keypass android \\"
echo "  -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000"
echo "${green}============================${nocolor}"
