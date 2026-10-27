# Bike Computer — Waveshare ESP32-S3-Touch-LCD-1.28-B firmware (ESP-IDF 5.5.x).
# Third-party components are vendored under components/ (see components/VENDORED.md); the component manager is off so the
# build never needs the internet.
cmake_minimum_required(VERSION 3.16)
set(ENV{IDF_COMPONENT_MANAGER} 0)
set(PROJECT_VER "0.7.4-rc1")
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(bike_computer)
