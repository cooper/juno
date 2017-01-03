# Copyright (c) 2009-16, Mitchell Cooper
#
# @name:            "ircd::message"
# @package:         "message"
# @description:     "represents an IRC message"
# @version:         ircd->VERSION
# @no_bless:        1
# @preserve_sym:    1
#
# @author.name:     "Mitchell Cooper"
# @author.website:  "https://github.com/cooper"
#
package message;

use warnings;
use strict;
use utf8;

use Scalar::Util 'blessed';
use utils qw(trim col ref_to_list);

our ($api, $mod, $pool, $me);
our $TRUE      = \'__TAG_TRUE__';

sub new {
    my ($class, @opts) = @_;
    my %opts;
    %opts = (data => shift @opts) if scalar @opts == 1;
    %opts = @opts if !%opts;

    # remove undefined tags
    if (my %tags = ref_to_list($opts{tags})) {
        defined $tags{$_} or delete $tags{$_} for keys %tags;
        $opts{tags} = \%tags;
    }

    # remove undefined parameters
    if (my $params = $opts{params}) {
        $opts{params} = [ grep defined, ref_to_list($params) ];
    }

    # create message
    my $msg = bless {
        tags => {},
        %opts
    }, $class;

    # parse data if provided
    $msg->parse if length $msg->{data};

    return $msg;
}

sub parse {
    my $msg = shift;
    return unless length $msg->data;
    my @words = split /\s+/, $msg->data;

    # $word_i = current word
    # $word_n = current word, exluding tags, source, command
    #
    my ($got_tags, $got_source, $got_command);
    my ($word_i, $word_n, $word, $last_word, $redo, @params) = (0, 0);
    WORD: while (defined($word = shift @words)) {
        my $f_char_ref = \substr($word, 0, 1);

        # first word could be message tags.
        if (!$got_source && !$got_tags && $word_i == 0 && $$f_char_ref eq '@') {
            $$f_char_ref = '';

            # separate tags by semicolon.
            my %tags;
            TAG: foreach my $tag (split /;/, $word) {

                # does it have a value?
                my $i = index $tag, '=';
                if ($i != -1) {
                    $tags{ substr $tag, 0, $i - 1 } =
                        _parse_value(substr $tag, ++$i, length $tag);
                    next TAG;
                }

                # no value; it's a boolean.
                $tags{$tag} = $TRUE;

            }

            ($got_tags, $msg->{tags}) = (1, \%tags);
            $word_n--;
            next WORD;
        }

        # could be the source if we haven't gotten it.
        if (!$got_command && !$got_source && $$f_char_ref eq ':') {
            $$f_char_ref = '';
            ($got_source, $msg->{source}) = (1, $word);
            $word_n--;
            next WORD;
        }

        # otherwise, this is the command if we haven't determined it.
        if (!$got_command) {
            ($got_command, $msg->{command}) = (1, $word);
            $word_n--;
            next WORD;
        }

        # this is for :rest.
        # TODO: I would like to do this without splitting again...
        $msg->{_rest}[$word_n] = col((split m/\s+/, $msg->data, $word_i + 1)[$word_i])
            if $word_n >= 0;

        # sentinel-prefixed final parameter.
        if ($$f_char_ref eq ':') {
            push @params, $msg->{_rest}[$word_n];
            last WORD;
        }

        # other parameter.
        push @params, $word;

    }
    continue {
        $word_i++;
        $word_n++;
        $last_word = $word;
    }

    $msg->{params} = \@params;
    return $msg;
}

# message tag escapes
my %escapes = (
    ':'  => ';',    # \: = semicolon - yes, this is intentional
    's'  => ' ',    # \s = space
    '\\' => '\\',   # \\ = slash
    'r'  => "\r",   # \r = CR
    'n'  => "\n"    # \n = LF
);

# parse message tag values
sub _parse_value {
    my ($value, $escaped) = '';
    for my $char (split //, shift) {
        if ($escaped) {
            $value .= $escapes{$char} // $char;
            undef $escaped;
            next;
        }
        if ($char eq '\\') {
            $escaped++;
            next;
        }
        $value .= $char;
    }
    return $value;
}

# escape message tag values
sub _escape_value {
    my ($in, $value) = (shift, '');
    return $in if ref $in && $in == $TRUE;
    my %r_escapes = reverse %escapes;
    for my $char (split //, $in) {
        if (my $e = $r_escapes{$char}) {
            $value .= "\\$e";
            next;
        }
        $value .= $char;
    }
    return $value;
}

sub data {
    my $msg = shift;
    return $msg->{data} if length $msg->{data};
    my @parts;

    # message tags.
    my ($t, $tagstr, @tags) = (0, '@', keys %{ $msg->tags });
    foreach my $tag (@tags) {
        my $value = $msg->tag($tag);
        next if !defined $value;
        $tagstr .= ref $value && $value == $TRUE ?
            $tag : $tag.'='._escape_value($value);
        $tagstr .= ';' unless $t == $#tags;
        $t++;
    }
    push @parts, $tagstr if @tags;

    # source.
    if (defined(my $source = $msg->source)) {
        if (blessed $source) {
            my ($str, $changed) = $msg->_stringify($source);
            $source = $changed   ? $str          :
            $source->can('full') ? $source->full : $source;
        }
        push @parts, ":$source" if length $source;
    }

    # command.
    push @parts, $msg->command if length $msg->command;

    # parameters.
    my ($p, @params) = (0, $msg->params);
    foreach my $param (@params) {

        # handle objects.
        if (blessed $param) {
            my ($str, $changed) = $msg->_stringify($param);
            $param = $changed            ? $str         :
                     $param->can('name') ? $param->name : $param;
        }

        # handle sentinel-prefixed final parameter.
        $param = ":$param" if $p == $#params && $param =~ m/\s+/;

        push @parts, $param;
        $p++;
    }

    return "@parts";
}

sub raw_cmd {    shift->{command}           }
sub command { uc shift->{command}           }
sub tags    { shift->{tags}                 }
sub tag     { shift->{tags}{+shift}         }
sub params  { @{ shift->{params} || [] }    }
sub param   { shift->{params}[shift]        }
sub event   { shift->{_event}               }

# TODO: these
sub source_nick  { ... }
sub source_ident { ... }
sub source_host  { ... }

# source always returns an object.
# if an object cannot be found, it returns undef.
sub source {
    my $msg = shift;
    my $source = $msg->{source} or return;

    # it's a string. do a lookup.
    if (!blessed $source) {

        # is there code for looking up sources?
        my ($obj, $changed) = $msg->_objectify($source);
        return $obj if $changed;

        # if not, assume the client protocol.

        # nickname lookup.
        $source = $pool->lookup_user_nick($1) if $source =~ m/^(.+)!.*@.*/;

        # server lookup. fall back to nickname again
        # (e.g. :nick COMMAND w/o ident or host)
        $source ||=
            $pool->lookup_server_name($source) ||
            $pool->lookup_user_nick($source);

        $msg->{source} = $source if $source;
        return $source;
    }

    # it's a connection object.
    #    if registered, use the user or server object.
    #    if not registered, use the connection object.
    if ($source->isa('connection')) {
        return $source->{type} || $source;
    }

    # it's some other object.
    return $msg->{source};

}

# my ($ok, @params) = $msg->parse_params($param_string)
sub parse_params {
    my ($msg, $param_string) = @_;
    my @parameters = split /\s+/, $param_string;

    # code to find matchers from the package.
    my $find_code = sub {
        my $type  = shift;
        ($msg->{param_package} || __PACKAGE__)->can("_param_$type") ||
            __PACKAGE__->can("_any_$type");
    };

    # parse argument type attributes and required parameters.
    my $required_parameters = 0; # number of parameters that will be checked
    my @match_attr;              # matcher attributes (i.e. opt)
    my @match_attr_keys;         # matcher attribute keys in order
    my $i = -1;
    foreach (@parameters) { $i++;

        # type(attribute1,att2:val,att3)
        if (/(.+)\((.+)\)/) {
            $parameters[$i] = $1;
            my $attributes = {};
            my @keys;

            # get the values of each attribute.
            foreach (split ',', $2) {
                my $attr = trim($_);
                my ($name, $val) = split /[:=]/, $attr, 2;
                $attributes->{$name} = defined $val ? $val : 1;
                push @keys, $name;
            }

            $match_attr[$i]      = $attributes;
            $match_attr_keys[$i] = \@keys;
        }

        # no attribute list, no attributes.
        else {
            $match_attr[$i]      = {};
            $match_attr_keys[$i] = [];
        }

        # unless there is an 'opt' (optional) attribute
        # or it is one of these fake parameters,
        # increase the required parameter count.
        next if $match_attr[$i]{opt};
        next if substr($_, 0, 1) eq '-'; # ex: -command or -oper

        $required_parameters++;
    }

    # $param_i = current actual parameter index
    # $match_i = current matcher index
    # @final   = the modified parameter list
    my ($param_i, $match_i, @final) = (-1, -1);

    # check argument count.
    my @params = $msg->params;
    if (scalar @params < $required_parameters) {
        $msg->source->numeric(ERR_NEEDMOREPARAMS => $msg->command)
            if $msg->source && $msg->source->isa('user');
        return;
    }

    foreach (@parameters) {
        $match_i++;
        my $attrs = $match_attr[$match_i];
        my $attr_keys = $match_attr_keys[$match_i];

        # so basically the dash (-) means that this will not be
        # counted in the required parameters AND that it does
        # not actually have a real parameter associated with it.
        # if it does use a real parameter, DO NOT USE THIS!
        # use (opt) instead if that is the case.

        # is this a fake (ignored) matcher?
        my ($type, $fake, @res);
        if (s/^-//) { $fake = 1  }
        else        { $param_i++ }
        my $type  = $_;
        my $param = $params[$param_i];

        # if this is not a fake matcher, and if there is no REAL parameter,
        # and the parameter is not marked as optional, give up.
        return if !$fake && !defined $param && !$attrs->{opt};

        # skip this parameter.
        if ($type eq 'skip') {
            next;
        }

        # any string.
        elsif ($type eq '*' || $type eq 'any') {
            @res = $param;
        }

        # rest of the arguments as a list.
        elsif ($type eq '@rest' || $type eq '...') {
            @res = @params[$param_i..$#params];
        }

        # rest of arguments, including unaltered whitespace.
        elsif ($type eq ':rest') {
            @res = $msg->{_rest}[$param_i];
        }

        # parameter as a certain type.
        # -tag.the_type(the_name, other opts...)
        elsif ($type =~ m/^tag\.(\w+)$/ && @$attr_keys) {

            # the parameter is the value of the tag in the message.
            $param = $msg->tag($1);

            # the first attribute is the type
            $type = shift @$attr_keys;
            delete $attrs->{$type};
        }

        # at this point, we have to have a code to handle this.
        if (!@res && defined $param && (my $param_code = $find_code->($type))) {
            @res = $param_code->($msg, $param, $attrs);
        }

        # still nothing, and the parameter isn't optional.
        return if !@res && !$attrs->{opt};

        push @final, @res;
    }
    return (1, @final);
}

# object->string. returns ($string, $changed)
sub _stringify {
    my ($msg, $possible_object) = @_;
    my $code = $msg->{stringify_function};
    if (!blessed $possible_object || !$code || ref $code ne 'CODE') {
        return $possible_object;
    }
    my $string = $code->($possible_object);
    return wantarray ? ($string, 1) : $string;
}

# string->object. returns ($object, $changed)
sub _objectify {
    my ($msg, $possible_id) = @_;
    my $code = $msg->{objectify_function};
    if (blessed $possible_id || !$code || ref $code ne 'CODE') {
        return $possible_id;
    }
    my $object = $code->($possible_id);
    return wantarray ? ($object, 1) : $object;
}

############################################
### Protocol-independent parameter types ###
############################################

# -message: inserts the message object.
sub _any_message {
    my ($msg, $param, $opts) = @_;
    return $msg;
}

# -event: inserts the event fire object.
sub _any_event {
    my ($msg, $param, $opts) = @_;
    return $msg->{_event};
}

# -data: inserts the raw line of data.
sub _any_data {
    my ($msg, $param, $opts) = @_;
    return $msg->{data};
}

# -command: inserts the command name.
sub _any_command {
    my ($msg, $param, $opts) = @_;
    return $msg->{command};
}

#######################################
### Client protocol parameter types ###
#######################################

# -oper: checks if oper flags are present.
sub _param_oper {
    my ($msg, $param, $opts) = @_;
    my $is_irc_cop = $msg->source->is_mode('ircop');
    my @flags = keys %$opts;
       @flags = 'do that' if !@flags;
    foreach my $flag (@flags) {
        next if $is_irc_cop && $msg->source->has_flag($flag);
        $msg->source->numeric(ERR_NOPRIVILEGES => $flag);
        return;
    }

    # mark it as optional to say it's ok.
    $opts->{opt}++;
    return;
}

# server: match a server name.
sub _param_server {
    my ($msg, $param, $opts) = @_;
    my $server = $pool->lookup_server_name($param);

    # not found, send no such server.
    if (!$server) {
        $msg->source->numeric(ERR_NOSUCHSERVER => $param);
        return;
    }

    return $server;
}

# server_mask: match a mask to a single server.
sub _param_server_mask {
    my ($msg, $param, $opts) = @_;

    # if it's *, always use the local server.
    if ($param eq '*') {
        return $me;
    }

    # otherwise, find the first server to match.
    my $server = $pool->lookup_server_mask($param);

    # not found, send no such server.
    if (!$server) {
        $msg->source->numeric(ERR_NOSUCHSERVER => $param);
        return;
    }

    return $server;
}

# user: match a nickname.
sub _param_user {
    my ($msg, $param, $opts) = @_;
    my $nickname = (split ',', $param)[0];
    my $user = $pool->lookup_user_nick($nickname);

    # not found, send no such nick.
    if (!$user) {
        $msg->source->numeric(ERR_NOSUCHNICK => $nickname);
        return;
    }

    return $user;
}

# channel: match a channel name.
sub _param_channel {
    my ($msg, $param, $opts) = @_;
    my $chaname = (split ',', $param)[0];
    my $channel = $pool->lookup_channel($chaname);

    # not found, send no such channel.
    if (!$channel) {
        $msg->source->numeric(ERR_NOSUCHCHANNEL => $chaname);
        return;
    }

    # if 'inchan' attribute, the requesting user must be in the channel.
    if ($opts->{inchan} && !$channel->has_user($msg->source)) {
        $msg->source->numeric(ERR_NOTONCHANNEL => $channel->name);
        return;
    }

    return $channel;
}

#################################
### Server message forwarding ###
#################################

# forward to all servers except the source.
sub forward {
    my ($msg, $e_name, $amnt) = (shift, shift, 0);
    my $server = $msg->{_physical_server} or return;

    # send to all children.
    foreach ($me->children) {

        # don't send to servers who haven't received my burst.
        next unless $_->{i_sent_burst};

        # don't send to the server we got it from.
        next if $_ == $server;

        $amnt++ if $_->fire_command($e_name => @_);
    }
    return $amnt;
}

# forward to all servers, even the source.
sub forward_plus_one {
    my ($msg, $e_name, $amnt) = (shift, shift, 0);
    my $server = $msg->{_physical_server} or return;

    # send to all children.
    foreach ($me->children) {

        # don't send to servers who haven't received my burst.
        next unless $_->{i_sent_burst};

        $amnt++ if $_->fire_command($e_name => @_);
    }
    return $amnt;
}

# forward to specific server(s).
sub forward_to {
    my ($msg, $target, $e_name, @args) = @_;
    blessed $target or return;
    my $amnt = 0;

    # directly to a server or its location.
    if ($target->isa('server')) {
        $target = $target->{conn} ? $target : $target->{location};
        return 0 if $msg->{_physical_server} == $target;
        $amnt++  if $target->fire_command($e_name => @args);
        return $amnt;
    }

    # to a user's server location.
    if ($target->isa('user')) {
        $target = $target->{location};
        return 0 if $msg->{_physical_server} == $target;
        $amnt++  if $target->fire_command($e_name => @args);
        return $amnt;
    }

    # to servers with members in a channel.
    if ($target->isa('channel')) {
        my %sent = ( $msg->{_physical_server} => 1 );
        foreach my $user ($target->users) {
            next if $sent{ $user->{location} };
            $amnt++ if $user->{location}->fire_command($e_name => @args);
            $sent{ $user->{location} }++;
        }
    }

    return 0;
}

# forward to all servers matching a mask except the source.
# returns true if the mask does NOT match the local server.
sub forward_to_mask {
    my ($msg, $mask, $e_name, @args) = @_;
    my $server = $msg->{_physical_server} or return;

    # send to all servers matching the mask.
    my ($amnt, $matches_me) = 0;
    foreach ($pool->lookup_server_mask($mask)) {

        # don't send to servers who haven't received my burst.
        next unless $_->{i_sent_burst};

        # don't send to the server we got it from.
        next if $_ == $server;

        $matches_me++, next if $_ == $me;
        $amnt++ if $_->fire_command($e_name => @args);
    }

    return ($amnt, !$matches_me) if wantarray;
    return !$matches_me;
}

$mod
