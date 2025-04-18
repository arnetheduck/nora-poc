## Build instructions

Using [nimble 0.18.0+](https://github.com/nim-lang/nimble/releases):

```sh
nimble setup -l
nimble shell
nim c -r nora/nora
```

#### Android
Works on MacOs and Linux
Might work on Windows

```sh
nimble setup
# installing dependencies and configuring the environment
nimble setup_android
# build, deploy and run
nimble android_run
```