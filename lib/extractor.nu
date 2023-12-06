def extract [input act args?] {
    match $act {
        from-json => {
            $input | from json
        }
        prefix => {
            $"($args)($input)"
        }
        index => {
            $input | get $args
        }
        field => {
            if ($args | is-empty) {
                $input
            } else {
                if $args in $input {
                    $input | get $args
                } else {
                    null
                }
            }
        }
        trim => {
            $input | str trim
        }
        regexp => {
            $input | parse -r $args | get 0?.capture0?
        }
        only-nums => {
            $input | parse -r '(?P<v>[0-9\.\-]+)' | get 0?.v?
        }
        github => {
            let ex = [
                {field: 'tag_name'}
                {trim: null }
                {only-nums: null} ]
            run-extractors ($input | from json) $ex
        }
    }
}

export def run [input extractors] {
    $extractors
    | reduce -f $input {|x, acc|
        let r = $x | record-to-struct k v
        extract $acc $r.k $r.v
    }
}
