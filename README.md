# Nora the Web3 API explorer

https://github.com/user-attachments/assets/e2451c44-4e3b-44fa-926b-01fdc39d89f5

## Build instructions

Using [nimble 0.18.0+](https://github.com/nim-lang/nimble/releases):

```sh
nimble setup -l
nimble shell
nim c -r src/nora
```

#### Android
Works on MacOs and Linux

Might work on Windows

```sh
nimble setup
# installing dependencies and configuring the environment
nimble setup_android
# build, deploy and run
# Make sure there's an android device/emulator attached

nimble android_run
```

#### Building as a qml plugin
```sh
nimble setup
nimble qml_plugin_build
```
The plugin must be available to the app by specifying import path. It can be
done in multiple ways (https://doc.qt.io/qt-6/qtqml-syntax-imports.html#qml-import-path).
From QML the plugin can be loaded by
```qml
import Nora
```
Currently, the plugin sets the context property `main` in the same way as it's
done in the full Nora app.

> [!NOTE]
> Because of the current limitations of seaqt, the app using the plugin must
> register the module by calling `qmlRegisterModule("Nora", 1, 0);` in order
> to make the qml imports working. In the future this will be replaced by
> registration directly in the plugin code.
