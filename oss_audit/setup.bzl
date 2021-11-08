"""Macro to set-up dependencies of oss_audit rule"""

load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")
load("@rules_python//python:pip.bzl", "pip_install")

def rules_oss_audit_setup():
    # use maybe
    pip_install(
        name = "oss_audit_deps",
        requirements = "@rules_oss_audit//oss_audit/tools:requirements.txt",
    )

    bazel_skylib_workspace()
