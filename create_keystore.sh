#!/bin/bash

keytool -genkey -v -keystore keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias app -storepass qwerty -keypass qwerty -dname "CN=Test, OU=Dev, O=Test, L=City, S=Region, C=EN"
