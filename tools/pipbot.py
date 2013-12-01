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
	print "    pipbot build <target> <build>"
	print "        Build a website configuration of type <build> for destination <target>"
	print ""
	print "    pipbot deploy [<target> <build>]"
	print "        Deploy a build website configuration to <target>"
	print ""
	print "    pipbot version"
	print "        Show the current project version"
	print ""
	print "    pipbot wtf"
	print "        Show the current project configuration"
	print ""
	print "    pipbot issue <command>"
	print "        Issue tracker commands:"
	print "          list        List all issues"
	print "          show        Show an issue's details"
	print "          open        Open (or reopen) an issue"
	print "          close       Close an issue"
	print "          edit        Modify an existing issue"
	print "          comment     Leave a comment on an issue"
	print "          label       Create, list, modify, or delete labels"
	print "          assign      Assign an issue to yourself (or someone else)"
	print "          milestone   Manage project milestones"
	print ""
	print "    pipbot new <feature>"
	print "        Start work on a new feature branch"
	print ""
	print "    pipbot pause"
	print "        Pause work on the current feature branch"
	print ""
	print "    pipbot close"
	print "        Complete work on the current feature branch"
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


def run(cmd, echo=True):
	if echo == True:
		print "$ " + cmd

	ret = os.system(cmd)
	if ret != 0:
		raise Exception('Command returned error code {0}'.format(ret))


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

	try:
		run("./autogen.sh")
		run("./configure " + configure_args)
		run("make clean all")
	except:
		return 2

	return 0


def deploy(args):

	# Support 'deploy <target> <build>' syntax
	if len(args) == 2:
		build(args[0], args[1])

	try:
		run("make install")
	except:
		return 2


def is_number(s):
	try:
		int(s)
		return True
	except ValueError:
		return False

def new(name):

	try:
		if is_number(name) == True:
			run("./tools/ghi show " + name, False)

		run("./tools/workflow new " + name, False)
		return 0
	except:
		return 2

def pause():

	try:
		run("./tools/workflow pause", False)
		return 0
	except:
		return 2

def close():

	try:
		run("./tools/workflow close", False)
		return 0
	except:
		return 2

def issue(args):

	try:
		run("./tools/ghi " + " ".join(args), False)
		return 0
	except:
		return 2

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


def get_configuration():
	file = open("config.summary", "r")
	return file.read()

def process_command(command, args):

	if command == "help":
		print_help()
		return 0

	elif command == "build":
		if len(args) != 2:
			print "Usage: pipbot build <target> <build>"
			return 1

		return build(args[0], args[1])

	elif command == "deploy":
		return deploy(args)

	elif command == "version":
		print get_version_string()
		return 0

	elif command == "wtf":
		print get_configuration()
		return 0

	elif command == "issue":
		return issue(args)

	elif command == "new":
		if len(args) != 1:
			print "Usage: pipbot new <feature>"
			return 1

		return new(args[0])

	elif command == "pause":
		return pause()

	elif command == "close":
		return close()

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
