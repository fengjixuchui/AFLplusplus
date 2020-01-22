#!/usr/bin/awk -f

# getopt.awk --- Do C library getopt(3) function in awk

# External variables:
#    Optind -- index in ARGV of first nonoption argument
#    Optarg -- string value of argument to current option
#    Opterr -- if nonzero, print our own diagnostic
#    Optopt -- current option letter

# Returns:
#    -1     at end of options
#    "?"    for unrecognized option
#    <c>    a character representing the current option

# Private Data:
#    _opti  -- index in multiflag option, e.g., -abc

function getopt(argc, argv, options,    thisopt, i)
{
    if (length(options) == 0)    # no options given
        return -1

    if (argv[Optind] == "--") {  # all done
        Optind++
        _opti = 0
        return -1
    } else if (argv[Optind] !~ /^-[^:[:space:]]/) {
        _opti = 0
        return -1
    }
    if (_opti == 0)
        _opti = 2
    thisopt = substr(argv[Optind], _opti, 1)
    Optopt = thisopt
    i = index(options, thisopt)
    if (i == 0) {
        if (Opterr)
            printf("%c -- invalid option\n", thisopt) > "/dev/stderr"
        if (_opti >= length(argv[Optind])) {
            Optind++
            _opti = 0
        } else
            _opti++
        return "?"
    }
    if (substr(options, i + 1, 1) == ":") {
        # get option argument
        if (length(substr(argv[Optind], _opti + 1)) > 0)
            Optarg = substr(argv[Optind], _opti + 1)
        else
            Optarg = argv[++Optind]
        _opti = 0
    } else
        Optarg = ""
    if (_opti == 0 || _opti >= length(argv[Optind])) {
        Optind++
        _opti = 0
    } else
        _opti++
    return thisopt
}

BEGIN {
    Opterr = 1    # default is to diagnose
    Optind = 1    # skip ARGV[0]

    # test program
    if (_getopt_test) {
        while ((_go_c = getopt(ARGC, ARGV, "ab:cd")) != -1)
            printf("c = <%c>, Optarg = <%s>\n",
                                       _go_c, Optarg)
        printf("non-option arguments:\n")
        for (; Optind < ARGC; Optind++)
            printf("\tARGV[%d] = <%s>\n",
                                    Optind, ARGV[Optind])
    }
}

function usage() {
   print \
"Usage: afl-cmin [ options ] -- /path/to/target_app [ ... ]\n" \
"\n" \
"Required parameters:\n" \
"\n" \
"  -i dir        - input directory with starting corpus\n" \
"  -o dir        - output directory for minimized files\n" \
"\n" \
"Execution control settings:\n" \
"\n" \
"  -f file       - location read by the fuzzed program (stdin)\n" \
"  -m megs       - memory limit for child process ("mem_limit" MB)\n" \
"  -t msec       - run time limit for child process (none)\n" \
"  -Q            - use binary-only instrumentation (QEMU mode)\n" \
"  -U            - use unicorn-based instrumentation (unicorn mode)\n" \
"\n" \
"Minimization settings:\n" \
"  -C            - keep crashing inputs, reject everything else\n" \
"  -e            - solve for edge coverage only, ignore hit counts\n" \
"\n" \
"For additional tips, please consult docs/README.md\n" \
"\n" \
      > "/dev/stderr"
   exit 1
}

function exists_and_is_executable(binarypath) {
  return 0 == system("test -f "binarypath" -a -x "binarypath)
}

BEGIN {
  print "corpus minimization tool for afl-fuzz++ (awk version)\n"
print "PATH="ENVIRON["PATH"]

  # defaults
  extra_par = ""
  # process options
  Opterr = 1    # default is to diagnose
  Optind = 1    # skip ARGV[0]
  while ((_go_c = getopt(ARGC, ARGV, "hi:o:f:m:t:eCQU?")) != -1) {
    if (_go_c == "i") {
      if (!Optarg) usage()
      if (in_dir) { print "Option "_go_c" is only allowed once" > "/dev/stderr"}
      in_dir = Optarg
      continue
    } else 
    if (_go_c == "o") {
      if (!Optarg) usage()
      if (out_dir) { print "Option "_go_c" is only allowed once" > "/dev/stderr"}
      out_dir = Optarg
      continue
    } else 
    if (_go_c == "f") {
      if (!Optarg) usage()
      if (stdin_file) { print "Option "_go_c" is only allowed once" > "/dev/stderr"}
      stdin_file = Optarg
      continue
    } else 
    if (_go_c == "m") {
      if (!Optarg) usage()
      if (mem_limit) { print "Option "_go_c" is only allowed once" > "/dev/stderr"}
      mem_limit = Optarg
      mem_limit_given = 1
      continue
    } else 
    if (_go_c == "t") {
      if (!Optarg) usage()
      if (timeout) { print "Option "_go_c" is only allowed once" > "/dev/stderr"}
      timeout = Optarg
      continue
    } else 
    if (_go_c == "C") {
      ENVIRON["AFL_CMIN_CRASHES_ONLY"] = 1
      continue
    } else 
    if (_go_c == "e") {
      extra_par = extra_par " -e"
      continue
    } else 
    if (_go_c == "Q") {
      if (qemu_mode) { print "Option "_go_c" is only allowed once" > "/dev/stderr"}
      extra_par = extra_par " -Q"
      if ( !mem_limit_given ) mem_limit = "250"
      qemu_mode = 1
      continue
    } else 
    if (_go_c == "U") {
      if (unicorn_mode) { print "Option "_go_c" is only allowed once" > "/dev/stderr"}
      extra_par = extra_par " -U"
      if ( !mem_limit_given ) mem_limit = "250"
      unicorn_mode = 1
      continue
    } else 
    if (_go_c == "?") {
      exit 1
    } else 
      usage()
  } # while options

  if (!mem_limit) mem_limit = 200
  if (!timeout) timeout = "none"

  # get program args
  i = 0
  prog_args_string = ""
  for (; Optind < ARGC; Optind++) {
    prog_args[i++] = ARGV[Optind]
    if (i > 1)
      prog_args_string = prog_args_string" "ARGV[Optind]
  }

  # sanity checks
  if (!prog_args[0] || !in_dir || !out_dir) usage()

  target_bin = prog_args[0] 

  # Do a sanity check to discourage the use of /tmp, since we can't really
  # handle this safely from an awk script.

  if (!ENVIRON["AFL_ALLOW_TMP"]) {
    dirlist[0] = in_dir
    dirlist[1] = target_bin
    dirlist[2] = out_dir
    dirlist[3] = stdin_file
    "pwd" | getline dirlist[4] # current directory
    for (dirind in dirlist) {
      dir = dirlist[dirind]

      if (dir ~ /^(\/var)?\/tmp/) {
        print "[-] Error: do not use this script in /tmp or /var/tmp." > "/dev/stderr"
        exit 1
      }
    }
    delete dirlist
  }

  # If @@ is specified, but there's no -f, let's come up with a temporary input
  # file name.

  trace_dir = out_dir "/.traces"

  if (!stdin_file) {
    found_atat = 0
    for (prog_args_ind in prog_args) {
      if ("@@" == prog_args[prog_args_ind]) {
        found_atat = 1
        break
      }
    }
    if (found_atat) {
      stdin_file = trace_dir "/.cur_input"
    }
  }

  # Check for obvious errors.

  if (mem_limit && mem_limit != "none" && mem_limit < 5) {
    print "[-] Error: dangerously low memory limit." > "/dev/stderr"
    exit 1
  }

  if (timeout && timeout != "none" && timeout < 10) {
    print "[-] Error: dangerously low timeout." > "/dev/stderr"
    exit 1
  }

  if (target_bin && !exists_and_is_executable(target_bin)) {

    "which "target_bin" 2>/dev/null" | getline tnew
    if (!tnew || !exists_and_is_executable(tnew)) {
      print "[-] Error: binary '"target_bin"' not found or not executable." > "/dev/stderr"
      exit 1
    }
    target_bin = tnew
  }

  if (!ENVIRON["AFL_SKIP_BIN_CHECK"] && !qemu_mode && !unicorn_mode) {
    if (0 != system( "grep -q __AFL_SHM_ID "target_bin )) {
      print "[-] Error: binary '"target_bin"' doesn't appear to be instrumented." > "/dev/stderr"
      exit 1
    }
  }

  if (0 != system( "test -d "in_dir )) {
    print "[-] Error: directory '"in_dir"' not found." > "/dev/stderr"
    exit 1
  }

  if (0 == system( "test -d "in_dir"/queue" )) {
    in_dir = in_dir "/queue"
  }

  system("rm -rf "trace_dir" 2>/dev/null");
  system("rm "out_dir"/id[:_]* 2>/dev/null")

  if (0 == system( "test -d "out_dir" -a -e "out_dir"/*" )) {
    print "[-] Error: directory '"out_dir"' exists and is not empty - delete it first." > "/dev/stderr"
    exit 1
  }

  if (stdin_file) {
    # truncate input file
    printf "" > stdin_file
    close( stdin_file )
  }

  if (!ENVIRON["AFL_PATH"]) {
    if (0 == system("test -f afl-cmin.awk")) {
      path = "."
    } else {
      "which afl-showmap 2>/dev/null" | getline path
    }
    showmap = path
  } else {
    showmap = ENVIRON["AFL_PATH"] "/afl-showmap"
  }

  if (!showmap || 0 != system("test -x "showmap )) {
    print "[-] Error: can't find 'afl-showmap' - please set AFL_PATH." > "/dev/stderr"
    exit 1
  }
  
  # get list of input filenames sorted by size
  i = 0
  while ("find "in_dir" -type f -exec stat -f '%z %N' \{\} \; | sort -n | cut -d' ' -f2-" | getline) {
    infilesSmallToBig[i++] = $0
  }
  in_count = i

  first_file = infilesSmallToBig[0]
  
  # Make sure that we're not dealing with a directory.

  if (0 == system("test -d "in_dir"/"first_file)) {
    print "[-] Error: The input directory contains subdirectories - please fix." > "/dev/stderr"
    exit 1
  }

  # Check for the more efficient way to copy files...
  if (0 != system("mkdir -p -m 0700 "trace_dir)) {
    print "[-] Error: Cannot create directory "trace_dir > "/dev/stderr"
    exit 1
  }

  if (0 == system("ln "in_dir"/"first_file" "trace_dir"/.link_test")) {
    cp_tool = "ln"
  } else {
    cp_tool = "cp"
  }

  # Make sure that we can actually get anything out of afl-showmap before we
  # waste too much time.

  print "[*] Testing the target binary..."

  if (!stdin_file) {
    system( "AFL_CMIN_ALLOW_ANY=1 \""showmap"\" -m "mem_limit" -t "timeout" -o \""trace_dir"/.run_test\" -Z "extra_par" -- \""target_bin"\" "prog_args_string" <\""in_dir"/"first_file"\"")
  } else {
    system("cp "in_dir"/"first_file" "stdin_file)
    system( "AFL_CMIN_ALLOW_ANY=1 \""showmap"\" -m "mem_limit" -t "timeout" -o \""trace_dir"/.run_test\" -Z "extra_par" -A \""stdin_file"\" -- \""target_bin"\" "prog_args_string" <dev/null")
  }

  first_count = 0

  runtest = trace_dir"/.run_test"
  while ((getline < runtest) > 0) {
    ++first_count
  }

  if (first_count) {
    print "[+] OK, "first_count" tuples recorded."
  } else {
    print "[-] Error: no instrumentation output detected (perhaps crash or timeout)." > "/dev/stderr"
    if (!ENVIRON["AFL_KEEP_TRACES"]) {
      system("rm -rf "trace_dir" 2>/dev/null")
    }
    exit 1
  }

  # Let's roll!

  #############################
  # STEP 1: Collecting traces #
  #############################

  print "[*] Obtaining traces for "in_count" input files in '"in_dir"'."

  cur = 0;
  if (!stdin_file) {
    while (cur < in_count) {
      fn = infilesSmallToBig[cur]
      ++cur;
      printf "\r    Processing file "cur"/"in_count
      system( "AFL_CMIN_ALLOW_ANY=1 \""showmap"\" -m "mem_limit" -t "timeout" -o \""trace_dir"/"fn"\" -Z "extra_par" -- \""target_bin"\" "prog_args_string" <\""in_dir"/"fn"\"")
    }
  } else {
    while (cur < in_count) {
      fn = infilesSmallToBig[cur]
      ++cur
      printf "\r    Processing file "cur"/"in_count
      system("cp "in_dir"/"fn" "stdin_file)
      system( "AFL_CMIN_ALLOW_ANY=1 \""showmap"\" -m "mem_limit" -t "timeout" -o \""trace_dir"/"fn"\" -Z "extra_par" -A \""stdin_file"\" -- \""target_bin"\" "prog_args_string" <dev/null")
    }
  }

  print ""


  #######################################################
  # STEP 2: register smallest input file for each tuple #
  # STEP 3: copy that file (at most once)               #
  #######################################################

  print "[*] Processing traces for input files in '"in_dir"'."

  cur = 0
  out_count = 0
  tuple_count = 0

  while (cur < in_count) {
    fn = infilesSmallToBig[cur]
    ++cur
    printf "\r    Processing file "cur"/"in_count
    # create path for the trace file from afl-showmap
    tracefile_path = trace_dir"/"fn
    # gather all keys, and count them
    while ((getline line < tracefile_path) > 0) {
        key = line
        if (!(key in key_count)) {
          ++tuple_count
        }
        ++key_count[key]
        if (! (key in best_file)) {
            # this is the best file for this key
            best_file[key] = fn
            # copy file unless already done
            if (! (fn in file_already_copied)) {
                system(cp_tool" "in_dir"/"fn" "out_dir"/"fn)
                file_already_copied[fn] = ""
                ++out_count
            }
        }
    }
    close(tracefile_path)
  }

  print ""
  print "[+] Found "tuple_count" unique tuples across "in_count" files."

  if (out_count == 1) {
    print "[!] WARNING: All test cases had the same traces, check syntax!"
  }
  print "[+] Narrowed down to "out_count" files, saved in '"out_dir"'."

  if (!ENVIRON["AFL_KEEP_TRACES"]) {
    system("rm -rf "trace_dir" 2>/dev/null")
  }

  exit 0
}