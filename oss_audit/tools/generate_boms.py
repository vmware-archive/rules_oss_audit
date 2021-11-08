# Copyright 2020-2021 VMware, Inc.
# SPDX-License-Identifier: Apache-2.0

"""
This script generates the BOM and BOM-issues files and validates
oss package usage.

To produce the BOM and BOM-issues files, three files are needed as input:
    1. Merged manifest file: all the packages used by a project
    2. Approved list: all oss packages approved for a release
    3. Denied list: all oss packages denied for a release

With these files, the two output manifests can be generated:
    1. BOM: contains list of packages consumed by a project with information
        about the package added from the approved/denied lists.
    2. BOM-issues: subset of the BOM, containing a list of packages consumed
        that are pending or denied for use.
Note: an empty mapping {} is written to the BOM and BOM-issues file if there
are no packages to write.

This script is sourced from oss_audit.

"""

import sys
import argparse
import yaml


def main():
    parser = argparse.ArgumentParser(description="Generate a BOM and BOM-issues file")
    parser.add_argument(
        "merged_manifests_path", help="Path to the merged manifests file"
    )
    parser.add_argument("bom_path", help="Output path for the BOM yaml file")
    parser.add_argument(
        "bom_issues_path", help="Output path for the BOM-issues yaml file"
    )
    parser.add_argument("--approved_list_path", help="Path to approved packages yaml")
    parser.add_argument("--denied_list_path", help="Path to denied packages yaml")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Throw error when denied packages are used",
    )
    parser.add_argument(
        "--suppress",
        action="append",
        default=[],
        help="List of suppressed denied packages",
    )
    args = parser.parse_args()

    approved_list = load_yaml_file(args.approved_list_path) if args.approved_list_path else {}
    denied_list = load_yaml_file(args.denied_list_path) if args.denied_list_path else {}
    merged_manifest = load_yaml_file(args.merged_manifests_path)

    # All packages that are included in a target, irrespective of package status
    bom = create_bom(merged_manifest, approved_list, denied_list)
    write_yaml(args.bom_path, bom)

    # Packages that are denied or pending
    issue_packages = set(bom) - set(approved_list)
    bom_issues = {key: bom[key] for key in issue_packages}
    write_yaml(args.bom_issues_path, bom_issues)

    # Open source packages that are denied
    denied_packages = set(denied_list).intersection(set(bom))
    unsuppressed = denied_packages.difference(args.suppress)
    if denied_packages:
        err_msg = """\
        _    _     _____ ____ _____
       / \  | |   | ____|  _ \_   _|
      / _ \ | |   |  _| | |_) || |
     / ___ \| |___| |___|  _ < | |
    /_/   \_\_____|_____|_| \_\|_|

    The following open source libraries found in this build are not allowed for
    use. They must be removed from product code in order for the build to comply
    with legal and license requirements:

      {}

    Catalog of packages used by your build:
      {}

    Catalog of denied packages:
      {}

    """.format(
            "\n      ".join(denied_packages), args.bom_path, args.denied_list_path
        )
        sys.stderr.write(err_msg)
        rc = 1 if args.strict and unsuppressed else 0
        sys.exit(rc)


def create_bom(merged_manifest, approved_list, denied_list):
    """Creates a BOM

    If a BOM package is approved or denied, the 'copyright_notice',
    'interaction_types', and 'resolution' will be copied over. Otherwise, these
    attributes will be added to the BOM with empty values.

    Args:
        merged_manifest: dictionary representing all the packages used by a
            project
        denied_list: dictionary representing the denied packages
        approved_list: dictionary representing the approved packages

    Returns:
        Dictionary representing the BOM.
    """
    resolved_packages = dict(list(approved_list.items()) + list(denied_list.items()))

    bom = merged_manifest.copy()
    for key in bom.keys():
        package_info = {
            "copyright_notices": "",
            "interaction_types": [],
            "resolution": "",
        }
        resolved_package = resolved_packages.get(key)
        # standardize all version numbers to be strings
        bom[key]["version"] = str(bom[key]["version"])
        if resolved_package is not None:
            for k in package_info.keys():
                package_info[k] = resolved_package[k]

        bom[key].update(package_info)

    return bom


def load_yaml_file(file_path):
    """Load a yaml file

    Args:
        file_path: path of the yaml file to load

    Returns:
        Object representing the YAML file
    """
    with open(file_path, "r") as fp:
        loaded_yaml = yaml.safe_load(fp)
    return loaded_yaml or {}


def write_yaml(file_path, packages):
    """Dump dictionary into yaml file

    Write the BOM or BOM-issues file by dumping a dictionary
    of packages into a given file in YAML format. See module docstring
    for description of output file contents.

    Args:
        file_path - string of path to output file
        packages - dictionary of packages to be dumped into a file

    Yields:
        File with given dictionary in yaml format
    """

    def string_representer(dumper, data):
        """Define YAML representer

        This representer represents multi-line strings as YAML block scalar
        literals while representing single-line strings as plain flow scalars.
        """
        if "\n" in data:
            return dumper.represent_scalar(
                "tag:yaml.org,2002:str", data.replace("\r", "").strip(), style="|"
            )
        return dumper.represent_scalar("tag:yaml.org,2002:str", data)

    yaml.add_representer(str, string_representer)

    with open(file_path, "w") as manifest:
        yaml.dump(packages, manifest, default_flow_style=False, allow_unicode=True)


if __name__ == "__main__":
    main()
