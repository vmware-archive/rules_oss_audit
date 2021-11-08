"""Macro to load external repositories used by the oss_audit rule"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def rules_oss_audit_dependencies():
    # use maybe
    http_archive(
        name = "rules_python",
        sha256 = "954aa89b491be4a083304a2cb838019c8b8c3720a7abb9c4cb81ac7a24230cea",
        url = "https://github.com/bazelbuild/rules_python/releases/download/0.4.0/rules_python-0.4.0.tar.gz",
    )

    http_archive(
        name = "bazel_skylib",
        sha256 = "1c531376ac7e5a180e0237938a2536de0c54d93f5c278634818e0efc952dd56c",
        urls = [
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.0.3/bazel-skylib-1.0.3.tar.gz",
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.0.3/bazel-skylib-1.0.3.tar.gz",
        ],
    )
