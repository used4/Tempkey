#!/data/data/com.termux/files/usr/bin/bash
# إعداد Dex2c على Termux مع Android SDK/NDK و CMake و apktool
# يعتمد على sdkmanager (رسمي وثابت) ويتجنب الروابط المؤقتة
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
pkg install -y ncurses-utils python git rust clang make wget unzip tar aria2 zlib libxml2 libxslt pkg-config libjpeg-turbo binutils openssl openjdk-17

# ================== حزم بايثون ==================
echo "${green}━━━ Python packages ━━━${nocolor}"
export LDFLAGS="-L${PREFIX}/lib/"
export CFLAGS="-I${PREFIX}/include/"
python -m pip install --upgrade pip wheel pillow
python -m pip install cython setuptools cryptography
CFLAGS="-Wno-error=incompatible-function-pointer-types -O0" python -m pip install lxml

# ================== Android SDK / cmdline-tools ==================
echo "${green}━━━ تهيئة Android SDK ━━━${nocolor}"
cd "$HOME"

# مرشّحات محتملة لمكان الـ SDK
SDK_HOME=""
SDK_CANDIDATES=("$HOME/android-sdk" "$HOME/.androidide" "$HOME/AndroidIDE" "$HOME/Android/Sdk")

# إذا android-sdk موجود مسبقًا، استخدمه أولًا
if [ -d "$HOME/android-sdk" ]; then
  SDK_HOME="$HOME/android-sdk"
fi

# إن ما تحدد، خُذ أول مسار موجود من المرشّحين
if [ -z "$SDK_HOME" ]; then
  for d in "${SDK_CANDIDATES[@]}"; do
    if [ -d "$d" ]; then
      SDK_HOME="$d"
      break
    fi
  done
fi

# إن ما لقيت، أنشئ $HOME/android-sdk وثبّت cmdline-tools عبر androidide-tools
if [ -z "$SDK_HOME" ]; then
  SDK_HOME="$HOME/android-sdk"
fi

# تأكّد من وجود cmdline-tools/sdkmanager
ensure_cmdline_tools () {
  if [ -x "$SDK_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    return 0
  fi
  echo "${yellow}cmdline-tools غير موجودة تحت $SDK_HOME. تثبيت عبر AndroidIDE tools...${nocolor}"
  rm -rf "$HOME/androidide-tools"
  git clone https://github.com/AndroidIDEOfficial/androidide-tools
  cd androidide-tools/scripts
  # سيحاول وضع الأدوات تحت $HOME/android-sdk افتراضيًا
  ./idesetup -c
  cd "$HOME"
  if [ ! -x "$SDK_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    echo "${red}فشل توفير sdkmanager. تأكّد من صلاحيات التخزين/الشبكة وحاول مجددًا.${nocolor}"
    exit 1
  fi
}
ensure_cmdline_tools

# أضف sdkmanager إلى PATH خلال الجلسة الحالية
export PATH="$PATH:$SDK_HOME/cmdline-tools/latest/bin"

# ================== قبول الرخص وتثبيت المكوّنات الرسمية ==================
echo "${green}━━━ قبول رخص Android SDK ━━━${nocolor}"
yes | sdkmanager --licenses >/dev/null 2>&1 || true

echo "${green}━━━ تثبيت NDK / CMake / أدوات البناء ━━━${nocolor}"
# اختر إصدارات مستقرة وشائعة
sdkmanager --sdk_root="$SDK_HOME" \
  "platform-tools" \
  "build-tools;34.0.4" \
  "cmake;3.22.1" \
  "ndk;26.1.10909125"

# ================== اكتشاف إصدار الـ NDK المثبّت ==================
NDK_DIR=""
if [ -d "$SDK_HOME/ndk" ] && ls -1 "$SDK_HOME/ndk" | grep -q .; then
  NDK_DIR="$(ls -d "$SDK_HOME/ndk"/* | sort -Vr | head -n1 || true)"
fi
if [ -z "$NDK_DIR" ]; then
  echo "${red}لم يتم العثور على مجلد NDK تحت: $SDK_HOME/ndk${nocolor}"
  exit 1
fi
ndk_version="$(basename "$NDK_DIR")"
echo "${yellow}تم العثور على NDK: ${ndk_version}${nocolor}"

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

# ================== ضبط PATH والمتغيرات (دائمًا) ==================
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

# أزل أي كتلة قديمة بنفس العنوان قبل الإضافة (اختياري، بسيط)
if [ -f "$shell_rc" ]; then
  sed -i '/^# ====== Android SDK\/NDK (أُضيفت بواسطة setup_dex2c\.sh) ======/,+10d' "$shell_rc" || true
fi

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
echo "تم إعداد Dex2c و Android SDK/NDK و CMake و apktool بنجاح."
echo "لتفعيل PATH فورًا في هذه الجلسة:"
echo "source \"$shell_rc\""
echo
echo "تحقق سريع:"
echo "  - sdkmanager --list | head"
echo "  - echo \"NDK at: \$ANDROID_NDK_ROOT\""
echo
echo "إن لم يكن لديك debug.keystore، أنشئه (من داخل مجلد Dex2c):"
echo "  mkdir -p \$HOME/Dex2c/keystore && keytool -genkey -v \\"
echo "    -keystore \$HOME/Dex2c/keystore/debug.keystore -storepass android -keypass android \\"
echo "    -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000"
echo "${green}============================${nocolor}"
