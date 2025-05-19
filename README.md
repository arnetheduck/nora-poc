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
