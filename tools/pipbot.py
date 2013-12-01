#!/usr/bin/env python

import json
import subprocess
import re
import os
from sys import argv
from sys import exit

projectdir = "/home/chris/src/pip-db/"
prefixdir = "/home/chris/.local/"
etcdir = prefixdir + "etc/pipbot/"

def print_help():
	print "                  ,--.    ,--."
	print "                 ((O ))--((O ))"
	print "               ,'_`--'____`--'_`."
	print "              _:  ____________  :_"
	print "             | | ||::::::::::|| | |"
	print "             | | ||::::::::::|| | |"
	print "             | | ||::::::::::|| | |"
	print "             |_| |/__________\\| |_|"
	print "               |________________|"
	print "            __..-'            `-..__"
	print "         .-| : .----------------. : |-."
	print "       ,\\ || | |\\______________/| | || /."
	print "      /`.\\:| | ||  __  __  __  || | |;/,'\\"
	print "     :`-._\\;.| || '--''--''--' || |,:/_.-':"
	print "     |    :  | || .----------. || |  :    |"
	print "     |    |  | || '--pipbot--' || |  |    |"
	print "     |    |  | ||   _   _   _  || |  |    |"
	print "     :,--.;  | ||  (_) (_) (_) || |  :,--.;"
	print "     (`-'|)  | ||______________|| |  (|`-')"
	print "      `--'   | |/______________\\| |   `--'"
	print "             |____________________|"
	print "              `.________________,'"
	print "               (_______)(_______)"
	print "               (_______)(_______)"
	print "               (_______)(_______)"
	print "               (_______)(_______)"
	print "              |        ||        |"
	print "              '--------''--------'"
	print ""
	print "Hello there. My name is pipbot. These are some of the things I can do:"
	print ""
	print "    pipbot list me <type>"
	print "    pipbot build me <build>"
	print ""


def fatal(msg):
	print msg
	exit(1)


def grep(regex, path):
	file = open(path, "r")

	match = ""

	for line in file:
		if re.search(regex, line):
			match += line

	return match


def get_json_from_file(name, path):
	json_file = open(path)
	json_data = json.load(json_file)
	json_file.close()

	for d in json_data:
		if d == name:
			return json_data[d]


def run(cmd):
	print "$ " + cmd
	os.system(cmd)

def build(target_name, build_name):

	target_json = get_json_from_file(target_name, etcdir + "targets.json")
	build_json = get_json_from_file(build_name, etcdir + "build.json")

	if target_json == None:
		print "Couldn't find target configuration '" + target_name + "'"
		return 1

	if build_json == None:
		print "Couldn't find build configuration '" + build_name + "'"
		return 1

	configure_args = " ".join(build_json["configure"]["args"] +
							  target_json["configure"]["args"] +
							  build_json["configure"]["env"] +
							  target_json["configure"]["env"])

	run("./autogen.sh")
	run("./configure " + configure_args)
	run("make clean all")

	return 0


def get_version():
	components = ["major", "minor", "micro"]
	values = []

	for component in components:
		line = grep("m4_define\(\\s*\\[pipdb_" + component + "_version\\]",
					projectdir + "configure.ac")
		match = re.match(r"^.*(?P<value>\d+).*$", line)
		value = match.group("value")
		values.append(value)

	return values


def get_version_string():
	return ".".join([str(i) for i in get_version()])


def process_command(command, args):

	if command == "help":
		print_help()
		return 0

	elif command == "build":
		if len(args) != 2:
			print "Usage: pipbot build <target> <build>"
			return 1

		return build(args[0], args[1])

	elif command == "version":
		print get_version_string()
		return 0

	else:
		print "I don't understand!"
		return 1


if __name__ == "__main__":

	if len(argv) > 1:
		command = str(argv[1]);
	else:
		print_help()
		exit(1)

	if len(argv) > 2:
		argv.pop(0)
		argv.pop(0)
		args = argv
	else:
		args = []

	os.chdir(projectdir)

	ret = process_command(command, args)
	exit(ret)
