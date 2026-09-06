#!/usr/bin/env just

default:
    @just --list

help:
    @just --list

set export

import "just/common.just"

import "just/build/linux.just"
import "just/build/macos.just"
import "just/build/windows.just"
import "just/build/all.just"

import "just/test/unit.just"
import "just/test/integration.just"
import "just/test/demo.just"
import "just/test/system.just"
import "just/test/coverage.just"

import "just/quality.just"
import "just/security.just"
