# rules_oss_audit

# Overview

With hundreds of thousands of open-source software (OSS) projects to choose
from, OSS is a vital component of almost any codebase. However, with over 80
unique licenses to comply with, each requiring unique care, complexity of
managing OSS usage cannot be overlooked. At VMware, like many other
organizations, product releases must comply with legal and license requirements
of the open source software being used. This process adds friction to the
development cycle and can result in product-release delays.

To address pain points in our workflow at VMware, we've created a new OSS
compliance workflow rooted in a Bazel rule, `oss_audit`. With `oss_audit`, we
accomplish 3 things:

1. Developers get a deterministic Bill of Materials with every build. There is
   no need for a separate OSS scanning step in the post-build stage, removing
   toil and room for error.

2. OSS validation happens at build time, so developers are quickly informed
   about any problems with OSS they have introduced or the existence of any
   denied open-source packages in the code base.

3. Bazel's multi-language support allows us to have one tool that works
   cross-platform.

### About the `oss_audit` workflow
The `oss_audit` rules uses a [Bazel aspect] that analyzes the dependency
graph of a build and collects license information about each package it finds.
Additionally, it consumes a list of approved and denied OSS packages (usually
from legal and security teams) to alert developers when denied packages are
being used. At VMware, the `approved_list.yaml` and `denied_list.yaml` files are
automatically generated by querying our OSS review tool and then checked into
source control for use by the next build.

Then, `oss_audit` outputs two files. First, it outputs a "BOM" yaml file, which
includes information on each OSS dependency. Second, it outputs a "BOM-issues"
file, containing a subset of OSS dependencies that have been denied for use or
that are still waiting for approval. At VMware, a Jenkins job consumes the "BOM"
to file any new OSS packages with our OSS review tool. Then, people from the
legal and security teams review the packages asynchronously.

`oss_audit` can audit any build target (such as a `java_binary`, `pkg_tar`,
etc.), but is currently only aware of Java dependencies via metadata provided
by [`rules_jvm_external`]. However, it can be extended to support other target
types as well. We are currently developing a prototype that supports C++ and
have plans to add support for other languages soon.

We hope our work inform the design of general-purpose licensing infrastructure
for the Bazel community.

Note: this solution doesn't currently support Windows.

[`rules_jvm_external`]: https://github.com/bazelbuild/rules_jvm_external
[Bazel aspect]: https://docs.bazel.build/versions/main/skylark/aspects.html

# Getting started
To use `oss_audit` in your project, first add it to your `WORKSPACE` file:

```starlark
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

RULE_OSS_AUDIT_COMMIT = "3885863c6953668c6a696b908d138264b76e3d63"

http_archive(
    name = "rules_oss_audit",
    sha256 = "87cd76d9e33a1e70fd99ab795b9e431a41feaeed8e96caaf7dba300fab804116",
    strip_prefix = "rules_oss_audit-%s" % RULE_OSS_AUDIT_COMMIT,
    url = "https://github.com/vmware/rules_oss_audit/archive/%s.zip" % RULE_OSS_AUDIT_COMMIT,
)
```

For basic usage, add the following code in your `BUILD` file:
```starlark
load("@oss_audit:java/oss_audit.bzl", "oss_audit")

oss_audit(
    name = "your-project-audit",
    src = ":your-target-to-audit-here",
    approved_list = "//your-project:approved_list.yaml",
    denied_list = "//your-project:denied_list.yaml",
)
```

# Try it out

### Overview

The Java project in this example is a project from the [bazelbuild/examples
repository](https://github.com/bazelbuild/examples/tree/main/java-maven). It is
an application that compares two numbers, using the [Ints.compare] method from
Guava. We've extended the project to create an `.rpm` package and a `.tar` file,
which we audit with `oss_audit`.

[Ints.compare]: https://guava.dev/releases/19.0/api/docs/com/google/common/primitives/Ints.html#compare(int,%20int)

### Prerequisites

* To run the example, [install Bazel](http://bazel.io/docs/install.html)
* To build the example RPM on macOS, install `rpmbuild` with `brew install rpm`

### Build & Run
**Clone the repo:**
```console
git clone git@github.com:vmware/rules_oss_audit.git
cd rules_oss_audit
```

**Audit the example `.rpm`:**
```console
$ bazel build //examples:rpm-oss-audit
```
The following files will be generated
- `bazel-bin/examples/oss-audit-example-rpm.bom.yaml`
- `bazel-bin/examples/oss-audit-example-rpm.bom-issues.yaml`

**Audit the example `.tar`:**

```bash
$ bazel build //examples:tar-oss-audit
```
The following files will be generated
- `bazel-bin/examples/oss-audit-example-tar.bom.yaml`
- `bazel-bin/examples/oss-audit-example-tar.bom-issues.yaml`

## Suppressing OSS Validation
By default, the build will fail if any denied OSS packages are found in the
code. Because of this, it may be convenient to temporarily suppress validation.

To suppress build failures due to a list of specific denied package, use the
`suppress` attribute of `oss_audit`. See `examples/BUILD.bazel` for an example.

# License
This project is licensed under the [Apache 2.0 license](./LICENSE)

# Get in touch
For questions, ideas, or just reaching out to the team, feel free to open a
discussion in our [GitHub Discussion
section](https://github.com/vmware/rules_oss_audit/discussions).

# Contributing

The rules_oss_audit project team welcomes contributions from the community. If
you wish to contribute code and you have not signed our contributor license
agreement (CLA), our bot will update the issue when you open a Pull Request. For
any questions about the CLA process, please refer to our [FAQ]. For more
detailed information, refer to [CONTRIBUTING.md](CONTRIBUTING.md).

[FAQ]: https://cla.vmware.com/faq
