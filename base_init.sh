#
# base_init.sh: top level script that should be sourced in, especially inside .bash_profile
#

do_init() {
    [[ -f $HOME/.base_debug ]] && export BASE_DEBUG=1
    [[ ! $ZSH_EVAL_CONTEXT ]] && {
        base_debug() { [[ $BASE_DEBUG ]] && printf '%(%Y-%m-%d:%H:%M:%S)T %s\n' -1 "DEBUG ${BASH_SOURCE[0]}:${BASH_LINENO[1]} $@" >&2; }
        base_error() {                      printf '%(%Y-%m-%d:%H:%M:%S)T %s\n' -1 "ERROR ${BASH_SOURCE[0]}:${BASH_LINENO[1]} $@" >&2; }
    } || {
        #
        # for zsh - it doesn't support time in printf
        #
        base_debug() { [[ $BASE_DEBUG ]] && printf '%s\n' "$(date) DEBUG ${BASH_SOURCE[0]}:${BASH_LINENO[1]} $@" >&2; }
        base_error() {                      printf '%s\n' "$(date) ERROR ${BASH_SOURCE[0]}:${BASH_LINENO[1]} $@" >&2; }
    }

    export BASE_SOURCES=()
    export BASE_OS=$(uname -s)
    export BASE_HOST=$(hostname -s)
}

set_base_home() {
    script=$HOME/.baserc
    [[ -f $script ]] && [[ ! $_baserc_sourced ]] && {
        base_debug "Sourcing $script"
        source "$script"
        _baserc_sourced=1
    }

    # set BASE_HOME to default in case it is not set
    [[ -z $BASE_HOME ]] && {
        local dir=$HOME/git/base
        base_debug "BASE_HOME not set; defaulting it to '$dir'"
        BASE_HOME=$dir
    }

    export BASE_HOME
}

source_it() {
    local lib iflag=0 sourced=0
    [[ $1 = "-i" ]] && { iflag=1; shift; }
    lib=$1
    if ((iflag)); then
        ((_interactive)) && [[ -f $lib ]] && { base_debug "(interactive) Sourcing $lib"; source "$lib"; sourced=1; }
    else
        [[ -f $lib ]] && { base_debug "Sourcing $lib"; source "$lib"; sourced=1; }
    fi
    ((sourced)) && BASE_SOURCES+=("$lib")
}

#
# source in libraries
#
import_libs_and_profiles() {
    local lib script bin team
    local -A teams

    source_it    "$BASE_HOME/lib/stdlib.sh"      # common library
    source_it -i "$BASE_HOME/company/lib/bashrc" # company-specific bashrc for interactive shells
    source_it -i "$BASE_HOME/user/$USER.sh"      # user-specific bashrc for interactive shells
    add_to_path "$BASE_HOME/company/bin"         # add company bin to PATH

    #
    # team specific actions
    #
    # Users choose teams by setting the "BASE_TEAM" variable in their user specific startup script
    # For example: BASE_TEAM=teamX
    #
    # Users can also set "BASE_SHARED_TEAMS" to more teams so as to share from those teams.
    # For example: BASE_SHARED_TEAMS="teamY teamZ" or
    #              BASE_SHARED_TEAMS=(teamY teamZ)
    #
    # We source the team specific startup script add the team bin directory to PATH, in the same order
    #
    teams=()
    for team in $BASE_TEAM $BASE_SHARED_TEAMS ${BASE_SHARED_TEAMS[@]}; do
        [[ ${teams[$team]} ]] && continue                    # skip if team was seen already
        source_it -i "$BASE_HOME/team/$team/lib/bashrc"      # team specific bashrc for interactive shells
        source_it    "$BASE_HOME/team/$team/lib/$team.sh"    # team specific startup library
        add_to_path  "$BASE_HOME/team/$team/bin"             # add team bin to PATH (gets priority over company bin)
        teams[$team]=1
    done
}

#
# A shortcut to refresh the base git repo
#
base_update() (
    [[ -d $BASE_HOME ]] && {
        cd "$BASE_HOME"
        git pull --rebase
    }
)

#
# base_wrapper
#
# This function is meant to be called by scripts that are built on top of base.
# base_wrapper is exported so that it is visible to sub processes started from the login shell.
# It discovers base_init and sources it.  It also looks at the command line arguments and interprets a few of those,
# like --debug.  It calls the main function the modified argument list.  The main function is expected to be defined by
# the calling script.
#
base_wrapper() {
    local grab_debug=0 arg args script
    [[ $1 = "-d" ]] && { grab_debug=1; shift; }
    [[ $BASE_HOME ]]    || { printf '%s\n' "ERROR: BASE_HOME is not set" >&2; exit 1; }
    [[ -d $BASE_HOME ]] || { printf '%s\n' "ERROR: BASE_HOME '$BASE_HOME'is not a directory or is not readable" >&2; exit 1; }
    script=$BASE_HOME/base_init.sh
    [[ -f $script ]]    || { printf '%s\n' "ERROR: base_init script '$script'is not present or is not readable" >&2; exit 1; }
    source "$script"
    ((grab_debug)) && {
        #
        # grab out '-debug' or '--debug' from argument list and set a global variable to turn on debug mode
        #
        for arg; do
            if [[ $arg = "-debug" ||  $arg = "--debug" ]]; then
                BASE_DEBUG=1
            elif [[ $arg = "-describe" ||  $arg = "--describe" ]]; then
                _describe
                exit $?
            elif [[ $arg = "-help" ||  $arg = "--help" ]]; then
                _help
                exit $?
            else
                args+=("$arg")
            fi
        done

        set -- "${args[@]}"
    }

    main "$@"
}

base_main() {
    do_init
    [[ $- = *i* ]] && _interactive=1 || _interactive=0
    set_base_home
    if [[ -d $BASE_HOME ]]; then
        import_libs_and_profiles   
        add_to_path "$BASE_HOME/bin"
    else
        base_error "BASE_HOME '$BASE_HOME' is not a directory or is not accessible"
    fi

    #
    # these functions need to be available to user's subprocesses
    #
    export -f base_update base_wrapper import
}

base_main
