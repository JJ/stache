
unit package Stache:auth<ben.little@fruition.net>:ver<0.0.0>;

enum trim is export(:Internals) <left right both none>;

class Block {
    has Str   $.body is required;
    has trim  $.trim-tag is required;
    has Bool  $.trim-left  is rw = False;
    has Bool  $.trim-right is rw = False;
    has $.next-block;
    method set-trim-left  { $.trim-left  = True }
    method set-trim-right { $.trim-right = True }
    method render(-->Str:D) {...}
}

class Body-Block is Block is export(:Internals) {
    method render(-->Str:D) {
        return '' if self.body ~~ / ^\s*$ /;
        my $body = self.body;
        $body .= subst(/^<ws>/,'') if self.trim-left;
        $body .= subst(/<ws>$/,'') if self.trim-right;
        return qq:to/EOF/;
        print q:to/EOS/.chomp;
        $body
        EOS
        EOF
    }
}

class Tmpl-Block is Block is export(:Internals) {
    method render(-->Str:D) { return self.body.trim ~ "\n" ; }
}

grammar Grammar is export(:Internals) {
    token TOP    { <body> | <stache> || $<unknown>=(.*) }
    token body   { <text> <stache>? }
    token stache { '{{' <trim-tag>? <text> '}}' <body>?  }
    token text     { <-[{}]>* }
    token trim-tag { <+[<>-]> }
    class Actions {
        method TOP($/) {
            my $block;
            our $*state = {};
            $block = $/<body>.made   if $/<body>.defined;
            $block = $/<stache>.made if $/<stache>.defined;
            my @blocks = ();
            my $*prev-block;
            my $next-block-should-be-trimmed = False;
            my $this-block-should-be-trimmed = False;
            while $block.defined {
                $block.set-trim-left if $this-block-should-be-trimmed;
                if $block.trim-tag ∈ (right,both) {
                    $next-block-should-be-trimmed = True;
                }
                if $*prev-block.defined and $block.trim-tag ∈ (left,both) {
                    $*prev-block.set-trim-right;
                }
                @blocks.push($block);
                NEXT {
                    $*prev-block = $block;
                    $block .= next-block;
                    $this-block-should-be-trimmed = $next-block-should-be-trimmed;
                }
            }
            make @blocks».render.join;
        }
        method body($/) {
            make Body-Block.new(
                body       => $/<text>.Str,
                trim-tag   => none,
                next-block => $/<stache>.made,
            );
        }
        method stache($/) {
            my $block = Tmpl-Block.new(
                body     => $/<text>.Str,
                trim-tag =>
                    $/<trim-tag>.defined ?? {
                        '<' => left,
                        '>' => right,
                        '-' => both,
                    }{$/<trim-tag>} !! none,
                next-block => $/<body>.made,
            );
            make $block;
        }
    }
    method parse($target, Mu :$actions = Actions, |c) {
        our $*block = Nil;
        callwith($target, :actions($actions), |c);
    }
}

sub MAIN(
    IO() $file, #| the template to render
    :$I,        #| include path
    :$debug = False,
) is export(:MAIN) {
    say render-template($file.slurp.trim, :I($I));
}

sub render-template(Str:D $template, :$I) is export(:Internals) {
    my IO::Path $fh;
    ENTER {
        my $id = sprintf '%d%d%d%d', (0..9).pick: 4;
        $fh = $*TMPDIR.add("stache-$id").IO;
    }
    LEAVE { $fh.unlink if $fh.defined; }
    my $script = Grammar.parse($template).made;
    fail "could not parse template" unless $script;
    my @flag-strings = ();
    $fh.spurt($script);
    @flag-strings.push("-I $I") if $I;
    my $proc = run « $*EXECUTABLE @flag-strings[] $fh », :out, :err;
    return $proc.out.slurp(:close).chomp;
}

