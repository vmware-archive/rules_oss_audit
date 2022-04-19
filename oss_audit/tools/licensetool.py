# Copyright 2020-2021 VMware, Inc.
# SPDX-License-Identifier: Apache-2.0

"""License info collection tool

Motivation
==========
This tool can be used to extract the existing license metadata using the jar's
location. This tool parses the POM file adjacent to the jar and fetch the
license metadata. This license info will be used in OSS manifest generation.

e.g.:
For this jar:
    https://jcenter.bintray.com/com/google/code/findbugs/jsr305/3.0.2/jsr305-3.0.2.jar

There a .pom file coexists with jar with same name in that location:
    jsr305-3.0.2.jar.jar
    jsr305-3.0.2.jar.pom

Where .pom file has license metadata in this format:
<...>
    <licenses>
		<license>
			<name>The Apache Software License, Version 2.0</name>
			<url>http://www.apache.org/licenses/LICENSE-2.0.txt‎</url>
			<distribution>repo</distribution>
		</license>
	</licenses>
<...>

So this tool can be used to generate the metadata:

    licensetool \
        https://jcenter.bintray.com/com/google/code/findbugs/jsr305/3.0.2/jsr305-3.0.2.jar \
        path/to/output/file

"""

from __future__ import print_function

import argparse
import logging
import os
import ssl
import sys
import time
import re
import urllib.request
from urllib.error import URLError, HTTPError
from xml.etree import ElementTree as et


def collect_license(url, output):
    """Fetch license metadata info using Jar location."""

    retry_status_codes = [429, 502, 503, 504]

    def _get_namespace(element):
        m = re.match("\{.*\}", element.tag)
        return m.group(0) if m else ""

    def _write_file(output, content):
        with open(output, "w") as f:
            f.write(content + "\n")

    def _request_pom(pom_url, tries=3):
        logging.debug("Downloading .pom from: {}".format(pom_url))
        for i in range(tries):
            try:
                return urllib.request.urlopen(pom_url)
            except HTTPError as e:
                logging.debug(
                    "Download failed: {}: {} {}".format(pom_url, e.code, e.reason)
                )
                if e.code not in retry_status_codes or i >= tries - 1:
                    break
            except URLError as e:
                logging.debug("Download failed: {}: {}".format(pom_url, e.reason))

            if i < tries - 1:
                logging.debug("Retrying in 3 seconds...")
                time.sleep(3)

        raise Exception("Unable to download .pom from: {}".format(pom_url))

    logging.basicConfig(
        level=logging.DEBUG,
        format="%(levelname)s: %(message)s",
    )

    if not url:
        logging.debug("Empty url, setting license value to 'UNKNOWN'")
        _write_file(output, "UNKNOWN")
        return

    if not os.environ.get("PYTHONHTTPSVERIFY", "") and getattr(
        ssl, "_create_unverified_context", None
    ):
        ssl._create_default_https_context = ssl._create_unverified_context

    try:
        # generate .pom file location
        path, jar_filename = url.rsplit("/", 1)
        pom_filename = jar_filename.replace(".jar", ".pom")
        pom_url = os.path.join(path, pom_filename)

        # Parse for licence element and convert as dict <key, value> pair
        # <licenses>
        #    <license>
        #      <name>Apache License, version 2.0</name>
        #      <url>http://www.apache.org/licenses/LICENSE-2.0.txt</url>
        #      <distribution>repo</distribution>
        #   </license>
        # </licenses>
        tree = et.ElementTree()
        pom = _request_pom(pom_url)
        tree.parse(pom)
        namespace = _get_namespace(tree.getroot())
        names = tree.findall("./{0}licenses/{0}license/{0}name".format(namespace))
        licenses = ";".join([item.text for item in names])
    except Exception as e:
        _write_file(output, "UNKNOWN")
        logging.info("Setting license value to 'UNKNOWN'. Reason: \n\t{}".format(e))
        return

    # For the case when no license metadata found in .pom file, license
    # defaults to 'UNKNOWN'
    if not licenses:
        licenses = "UNKNOWN"
        logging.debug(
            "No license metadata found in .pom file, setting license value to 'UNKNOWN'"
        )
    _write_file(output, licenses)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n")[0], fromfile_prefix_chars="@"
    )
    parser.add_argument("url", help="Jar file location url")
    parser.add_argument("output", help="Output file")
    parser.add_argument("--log_level", required=False, default="WARNING",help="Provide logging level. Example --log_level debug', default='warning'")

    args = parser.parse_args()
    logging.basicConfig(level=args.log_level)
    collect_license(args.url, args.output)


if __name__ == "__main__":
    main()
