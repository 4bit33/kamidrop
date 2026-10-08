#!/usr/bin/env bash
# Пакує Linux-збірку в архів: build/release/kamidrop-<версія>-linux-x64.tar.gz.
# Спершу: flutter build linux --release
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
name="kamidrop-$version-linux-x64"
stage="build/release/$name"
rm -rf "$stage" && mkdir -p "$stage"
cp -r build/linux/x64/release/bundle/. "$stage/"
cp linux/packaging/kamidrop.desktop linux/packaging/kamidrop.png "$stage/"
cat > "$stage/install.sh" <<'SH'
#!/usr/bin/env bash
# Встановлює KamiDrop для поточного користувача: ~/.local/opt/kamidrop + ярлик у меню.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.local/opt/kamidrop"
rm -rf "$dest" && mkdir -p "$dest" "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/256x256/apps"
cp -r "$here/." "$dest/"
ln -sf "$dest/kamidrop" "$HOME/.local/bin/kamidrop"
sed "s|^Exec=kamidrop|Exec=$dest/kamidrop|" "$here/kamidrop.desktop" > "$HOME/.local/share/applications/kamidrop.desktop"
cp "$here/kamidrop.png" "$HOME/.local/share/icons/hicolor/256x256/apps/kamidrop.png"
echo "KamiDrop встановлено: $dest (запуск — з меню застосунків або командою kamidrop)"
SH
chmod +x "$stage/install.sh"
tar -C build/release -czf "build/release/$name.tar.gz" "$name"
echo "build/release/$name.tar.gz"
