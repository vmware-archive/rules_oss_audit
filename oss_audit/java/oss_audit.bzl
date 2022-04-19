# Copyright 2020-2021 VMware, Inc.
# SPDX-License-Identifier: Apache-2.0

"""Utilities to help OSS tracking.

"""

load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

MavenBomInfo = provider(
    fields = {
        "deploy_env": "Depset: JARs provided by the deployment environment",
        "deploy_info": "Depset of tuples: " +
                       "<jar:File, maven_coordinates:str, url:str, srcjar_url:str>",
    },
    doc = """Provider for mapping JARs to their maven-coordinates.

    @unused deploy_env at this point. Needs to be cleaned up if not needed in
    final version.
    """,
)

def _aggregate_maven_info(targets):
    return [
        target[MavenBomInfo].deploy_info
        for target in targets
        if MavenBomInfo in target
    ]

def _collect_maven_bom_impl(_target, ctx):
    """Implements `_collect_maven_bom`.
    """
    deploy_env = getattr(ctx.rule.attr, "deploy_env", [])
    data = getattr(ctx.rule.attr, "data", [])
    srcs = getattr(ctx.rule.attr, "srcs", [])
    deps = getattr(ctx.rule.attr, "deps", [])
    exports = getattr(ctx.rule.attr, "exports", [])
    runtime_deps = getattr(ctx.rule.attr, "runtime_deps", [])
    jar = getattr(ctx.rule.attr, "jar", None)
    jar = [jar] if jar else []

    transitive_closure = deps + exports + runtime_deps + jar + srcs + data

    if JavaInfo not in _target:
        deploy_env_set = depset(
            [],
            transitive = [
                env[JavaInfo].compilation_info.runtime_classpath
                for env in deploy_env
                if JavaInfo in env
            ],
        )
        return [MavenBomInfo(
            deploy_info = depset(
                [],
                transitive = _aggregate_maven_info(transitive_closure),
            ),
            deploy_env = deploy_env_set,
        )]

    class_jar = _target[JavaInfo].outputs.jars[0].class_jar if _target[JavaInfo].outputs.jars else None
    info = []

    # Collect the source bundle url location, i.e., a direct link to the
    # downloadable source for the maven artifact.
    srcjar_url = None
    srcjar_target = getattr(ctx.rule.attr, "srcjar", None)
    if srcjar_target:
        srcjar_label_name = srcjar_target.label.name
        srcjar_url = srcjar_label_name.replace("v1/https/", "https://")

    # Collect maven coordicnates and jar locations.
    url = ""
    coordinate = ""
    tags = getattr(ctx.rule.attr, "tags", [])

    # Tracking all maven jars that have coordinates. The url can be empty for
    # internal jars. These internal jars are skipped from the final output
    # manifest file.
    for tag in tags:
        if tag.startswith("maven_coordinates="):
            coordinate = tag.split("=")[1]
        elif tag.startswith("maven_url="):
            url = tag.split("=")[1]
    if coordinate:
        info = [(class_jar, coordinate, url, srcjar_url)]

    deploy_env_set = depset(
        [],
        transitive = [
            env[JavaInfo].compilation_info.runtime_classpath
            for env in deploy_env
        ],
    )
    return [MavenBomInfo(
        deploy_info = depset(
            info,
            transitive = _aggregate_maven_info(transitive_closure),
        ),
        deploy_env = deploy_env_set,
    )]

_collect_maven_bom = aspect(
    attr_aspects = [
        "data",
        "srcs",
        "deps",
        "exports",
        "jar",
        "runtime_deps",
    ],
    doc = """Aspect to gather maven-coordinates and other info for a Java
    target and its dependencies.

    Given a target, we'll walk the attributes named by `attr_aspects` to extract
    `maven_coordinates` information and use that to generate oss manifest file.
    """,
    implementation = _collect_maven_bom_impl,
)

def _oss_audit_impl(ctx):
    """Implements `oss_audit`.
    """
    output_file_prefix = ctx.attr.output_file_prefix if ctx.attr.output_file_prefix else ctx.attr.src.label.name

    collected_data = sets.make()
    for _, maven_coordinate, jar_url, srcjar_url in ctx.attr.src[MavenBomInfo].deploy_info.to_list():
        sets.insert(collected_data, (maven_coordinate, jar_url, srcjar_url))

    bom_file = ctx.actions.declare_file(
        output_file_prefix + ".bom.yaml",
    )
    merged_manifests_file = ctx.actions.declare_file(
        output_file_prefix + ".merged_manifests.yaml",
    )
    bom_issues_file = ctx.actions.declare_file(
        output_file_prefix + ".bom-issues.yaml",
    )

    # Example entry in the manifest file:
    # com.google.code.findbugs:jsr305:3.0.2:
    #   jar_url: https://jcenter.bintray.com/com/google/code/findbugs/jsr305/3.0.2/jsr305-3.0.2.jar
    #   license: The Apache Software License, Version 2.0
    #   maven-artifactId: jsr305
    #   maven-groupId: com.google.code.findbugs
    #   modified: false
    #   name: com.google.code.findbugs:jsr305
    #   repository: Maven
    #   url: https://jcenter.bintray.com/com/google/code/findbugs/jsr305/3.0.2/jsr305-3.0.2-sources.jar
    #   version: 3.0.2

    submanifests = []
    submanifest_paths = []
    internal_jars = []
    for coord, jar_url, srcjar_url in sets.to_list(collected_data):
        name, version = coord.rsplit(":", 1)
        group_id, artifact_id = name.split(":", 1)

        # The jar_url will be empty for internal jars.
        if not jar_url:
            if ctx.attr.debug:
                internal_jars.append(coord)
            continue
        license = ctx.actions.declare_file(coord + ".license")
        submanifest = ctx.actions.declare_file(coord + ".submanifest")
        
        # Decide whether to show progress when running license tool
        progress_message = None
        if !ctx.attr.debug:
            progress_message = "Fetching license info {}".format(ctx.label)
        
        # Invoke _licensetool to produce .licence file that contains license metadata
        ctx.actions.run(
            outputs = [license],
            executable = ctx.executable._licensetool,
            arguments = [jar_url, license.path],
            progress_message = progress_message,
        )

        # Load from .license file and produce .submanifest file with other info
        # for one maven jar
        ctx.actions.run_shell(
            inputs = [license],
            outputs = [submanifest],
            arguments = [
                submanifest.path,
                coord,
                jar_url,
                license.path,
                group_id,
                artifact_id,
                name,
                srcjar_url if srcjar_url else "",
                version,
            ],
            command = """
set -e

cat > $1 <<EOF
$2:
  jar_url: $3
  license: $(<$4)
  maven-groupId: $5
  maven-artifactId: $6
  modified: 'no'
  name: $7
  repository: 'Maven'
  url: $8
  version: $9
EOF
""",
        )
        submanifests.append(submanifest)
        submanifest_paths.append(submanifest.path)

    # Merge submanifest files into one bom file
    ctx.actions.run_shell(
        outputs = [merged_manifests_file],
        inputs = submanifests,
        arguments = [merged_manifests_file.path] + submanifest_paths,
        command = """
set -e

outfile=$1; shift

if [ $# -ne 0 ]; then
    cat "$@" > $outfile
else
    # create empty merged manifest file if there are no submanifest files
    touch $outfile
fi
""",
    )

    # Generate BOM and BOM-issues files and validate OSS usage
    args = ctx.actions.args()
    inputs = [merged_manifests_file]
    args.add_all([merged_manifests_file, bom_file, bom_issues_file])
    if (ctx.file.approved_list):
        inputs.append(ctx.file.approved_list)
        args.add("--approved_list_path", ctx.file.approved_list.path)
    if (ctx.file.denied_list):
        inputs.append(ctx.file.denied_list)
        args.add("--denied_list_path", ctx.file.denied_list.path)
    if ctx.attr._strict_oss[BuildSettingInfo].value:
        args.add("--strict")
    args.add_all(ctx.attr.suppress, before_each = "--suppress")
    ctx.actions.run(
        outputs = [bom_file, bom_issues_file],
        executable = ctx.executable._generate_boms,
        inputs = inputs,
        arguments = [args],
        mnemonic = "OssAudit",
        progress_message = "Generating manifest files and validating Java OSS usage for {}".format(ctx.label),
    )

    if ctx.attr.debug:
        print(
            "The following internal jars are ignored for oss tracking",
            internal_jars,
        )  # buildifier: disable=print

    return [
        DefaultInfo(files = depset([
            bom_file,
            bom_issues_file,
        ])),
    ]

oss_audit = rule(
    implementation = _oss_audit_impl,
    doc = """
Produce maven information (coordinates, url, etc.) of Java binaries (and its
runtime dependencies) into a BOM and BOM-issues file. Internal jars are
excluded from the output list as they are not needed for oss tracking purpose.
Use `debug` option to log the list of skipped jars.

Output:
    DefaultInfo:
        files: depset containing the file with maven info.
""",
    # @unsorted-dict-items
    attrs = {
        "approved_list": attr.label(
            doc = "YAML file detailing packages that are approved for use",
            allow_single_file = True,
        ),
        "denied_list": attr.label(
            doc = "YAML file detailing packages that are denied for use",
            allow_single_file = True,
        ),
        "debug": attr.bool(
            doc = "Print some additional diagnostics useful for debugging",
            default = False,
        ),
        "output_file_prefix": attr.string(
            doc = "Prefix used in output file names. If not passed, defaults to the rpm name passed in src",
        ),
        "src": attr.label(
            doc = "Target to audit for OSS usage",
            aspects = [_collect_maven_bom],
            mandatory = True,
        ),
        "suppress": attr.string_list(
            doc = "List of denied OSS libraries(keys) to be suppressed/ignored during OSS package usage. Example package: maven:wsdl4j:wsdl4j:1.6.2",
        ),
        "_generate_boms": attr.label(
            doc = "Generates the BOM and BOM-issues files and validates oss package usage",
            default = "//oss_audit/tools:generate_boms",
            executable = True,
            cfg = "exec",
        ),
        "_licensetool": attr.label(
            doc = "Tool to extract existing license metadata",
            default = "//oss_audit/tools:licensetool",
            executable = True,
            cfg = "exec",
        ),
        "_strict_oss": attr.label(
            doc = "A flag to indicate whether use of denied packages will terminate a build",
            default = "//oss_audit:strict_oss",
            providers = [BuildSettingInfo],
        ),
    },
)
