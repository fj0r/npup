def interpret-common [os act] {
    let default = {
        setup:    {|p| $'echo start'}
        teardown: {|p| $'echo stop'}
        cargo:    {|p| $'cargo install ($p)'}
        stack:    {|p| $'stack install ($p)'}
        go:       {|p| $'go install ($p)'}
        pip:      {|x| $'pip3 install --break-system-packages --no-cache-dir ($x)'}
        npm:      {|p| $'npm install --location=global ($p)'}
    }
    let diff = {
        debian: {
            setup:    {|x| $'apt update; apt upgrade -y'}
            install:  {|x| $'DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends ($x)'}
            clean:    {|x| $'apt remove -y ($x)'}
            teardown: {|x| $'
                apt-get autoremove -y
                apt-get clean -y
                rm -rf /var/lib/apt/lists/*
            '}

        }
        arch: {
            setup:    {|x| $'pacman -Syy; pacman -Syu'}
            install:  {|x| $'pacman -S ($x)'}
            clean:    {|x| $'pacman -R ($x)'}
            teardown: {|x| $'rm -rf /var/cache/pacman/pkg'}
        }
        alpine: {
            install:  {|x| $'apk add ($x)'}
            clean:    {|x| $'apk del ($x)'}
        }
        redhat: {
            setup:    {|x| $'yum update; yum upgrade'}
            install:  {|x| $'yum install ($x)'}
            pip:      {|p| $'pip3 install --no-cache-dir ($p)'}
            clean:    {|x| $'yum remove ($x)'}
            teardown: {|x| $'yum clean all'}
        }
    }
    $default | merge ($diff | get $os) | get $act
}

def interpret-recipe [act] {
    let default = {
        log:      {|x| $"echo '($x)'"}
        mkdir:    {|x| $"mkdir -p ($x.target)"}
        git:      {|x| [
                        $"git clone --depth=($x.depth) ($x.url) ($x.target)"
                        $"cd ($x.target)"
                        "git log -1 --date=iso"
                       ] | str join (char newline)
                  }
        shell:    {|x| $x.args
                        | tap {|y| $x.runner? | not-empty } {|y|
                            let z = $y | str join ';'
                            $"($x.runner) '($z)'"
                        }
                        | tap {|y| $x.workdir? | not-empty } {|y|
                            [
                                $"cd ($x.workdir)"
                                $y
                            ] | str join (char newline)
                        }
                  }
        mv:       {|x| $"mv ($x.from) ($x.to)" }
        rm:       {|x| $"rm -rf ($x.target)" }
        env:      {|x| $"export ($x.key)=($x.value)(char newline)echo '($x.key)=($x.value)' >> /etc/environment"}
        env-pre:  {|x| [ $"export ($x.key)='($x.value):${($x.key)}'"
                         $"echo '($x.key)=($x.value):${($x.key)}' >> /etc/environment"
                       ] | str join (char newline)
                  }
        download: {|x|
                        let rn = if ($x.rename? | is-empty) { [] } else {
                            $x.rename
                            | each {|r| $"mv ($r.0) ($r.1)"}
                            | str join (char newline)
                        }
                        if ($x.workdir? | not-empty) {
                            let f = if $x.local {
                                $'cp ($x.url) ($x.workdir)'
                            } else {
                                $'wget -c ($x.url) -O ($x.workdir)'
                            }
                            [
                                $"cd ($x.workdir)"
                                $f
                                $"($x.decmp) ($x.target)"
                            ]
                        } else {
                            let s = if ($x.strip | is-empty) {
                                    []
                                } else {
                                    [ $'--strip-components=($x.strip)' ]
                                }
                            let o = if $x.override {
                                [">"]
                            } else {
                                ['-' ...$s '-C']
                            }
                            let f = if $x.override { [] } else { $x.filter }
                            let r = [
                                $"curl -sSL ($x.url)"
                                '|'
                                $x.decmp
                                ...$o
                                $x.target
                                ...$f
                            ]
                            | str join ' '
                            [$r]
                        }
                        | append $rn
                        | str join (char newline)
                  }
    }
    if ($act in $default) {
        $default | get $act
    } else {
        {|args| $"### no ($act)" }
    }
}

export def main [dry_run] {
    for x in $in {
        let stage = if $x.action == 'common' {
            let title = $"#################### ($x.context) ####################"
            let cmd = do (cmd-with-args (interpret-common $x.os $x.context)) $x.args
            [$title $cmd]
        } else {
            let title = $"### ($x.context)[($x.action)]"
            let cmd = do (interpret-recipe $x.action) $x
            [$title $cmd]
        }
        | str join (char newline)

        if $dry_run {
            print $stage
        } else {
            sh -c $"set -eux(char newline)($stage)"
        }
    }
}

