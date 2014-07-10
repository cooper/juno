# Copyright (c) 2009-14, Mitchell Cooper
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
use utils 'trim';

our ($api, $mod, $pool, $me);
our $TRUE      = '__TAG_TRUE__';
our $PARAM_BAD = '__PARAM_BAD__';

sub new {
    my ($class, %opts) = @_;
    my $msg = bless {
        tags => {},
        %opts
    }, $class;

    $msg->parse if length $opts{data};
    return $msg;
}

sub parse {
    my $msg = shift;
    return unless length $msg->data;
    my @words = split /\s+/, $msg->data;
    
    my ($got_tags, $got_source, $got_command, $got_sentinel);
    my ($word_i, $word, $last_word, @params) = 0;
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
                    $tags{ substr $tag, 0, $i - 1 } = substr $tag, ++$i, length $tag;
                    next TAG;
                }
                
                # no value; it's a boolean.
                $tags{$tag} = $TRUE;
                
            }
            
            # got the tags.
            ($got_tags, $msg->{tags}) = (1, \%tags);
            next WORD;
            
        }
        
        # could be the source if we haven't gotten it.
        if (!$got_command && !$got_source && $$f_char_ref eq ':') {
            $$f_char_ref = '';
            
            # got the source.
            ($got_source, $msg->{source}) = (1, $word);
            next WORD;
            
        }
        
        # otherwise, this is the command if we haven't determined it.
        if (!$got_command) {
        
            # got the command.
            ($got_command, $msg->{command}) = (1, $word);
            next WORD;
            
        }
        
        # sentinel-prefixed final parameter.
        # TODO: I would like to do this without splitting again...
        if ($$f_char_ref eq ':') {
            push @params, substr((split /\s+/, $msg->data, $word_i + 1)[$word_i], 1);
            last WORD;
        }
        
        # other parameter.
        push @params, $word;
    
    }
    continue {
        $word_i++;
        $last_word = $word;
    }
    
    $msg->{params} = \@params;
    return $msg;
}

sub data {
    my $msg = shift;
    return $msg->{data} if length $msg->{data};
    my @parts;
    
    # message tags.
    my ($t, $tagstr, @tags) = (0, '@', keys %{ $msg->tags });
    foreach my $tag (@tags) {
        my $value = $msg->tag($tag);
        $tagstr .= $value eq $TRUE ? $tag : "$tag=$value";
        $tagstr .= ';' unless $t == $#tags;
        $t++;
    }
    push @parts, $tagstr if @tags;
    
    # source.
    if (defined(my $source = $msg->source)) {
        $source = $source->full if blessed $source;
        push @parts, ":$source" if length $source;
    }
    
    # command.
    push @parts, $msg->command if length $msg->command;

    # arguments.
    my ($p, @params) = (0, $msg->params);
    foreach my $param (@params) {
    
        # handle objects.
        $param = $param->name if blessed $param && $param->can('name');
        
        # handle sentinel-prefixed final parameter.
        $param = ":$param" if $p == $#params && $param =~ m/\s+/;
        
        push @parts, $param;
        $p++;
    }
    
    return "@parts";
}

sub raw_cmd {    shift->{command}       }
sub command { uc shift->{command}       }
sub source  { shift->{source}           } # TODO: needs to always return object
sub tags    { shift->{tags}             }
sub tag     { shift->{tags}{+shift}     }
sub params  { @{ shift->{params} }      }
sub param   { shift->{params}[shift]    }

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

sub parse_params {
    my ($msg, $param_string) = @_;
    my @parameters = split /\s+/, $param_string;

    # parse argument type attributes and required parameters.
    my $required_parameters = 0; # number of parameters that will be checked
    my @match_attr;              # matcher attributes (i.e. opt)
    my $i = -1;
    foreach (@parameters) { $i++;
    
        # type(attribute1,att2:val,att3)
        if (/(.+)\((.+)\)/) {
            $parameters[$i] = $1;
            my $attributes = {};
            
            # get the values of each attribute.
            foreach (split ',', $2) {
                my $attr = trim($_);
                my ($name, $val) = split ':', $attr, 2;
                $attributes->{$name} = defined $val ? $val : 1;
            }
            
            $match_attr[$i] = $attributes;
        }
        
        # no attribute list, no attributes.
        else {
            $match_attr[$i] = {};
        }
        
        # unless there is an 'opt' (optional) attribute
        # or it is one of these fake parameters,
        next if $match_attr[$i]{opt};
        next if substr($_, 0, 1) eq '-'; # ex: -command or -oper
        
        # increase required parameter count.
        $required_parameters++;
        
    }
    
    # param_i = current actual parameter index
    # match_i = current matcher index
    # (because a matcher might not really be a parameter matcher at all)
    my (@final, %param_id);
    my ($param_i, $match_i) = (-1, -1);
        
    # check argument count.
    my @params = $msg->params;
    if (scalar @params < $required_parameters) {
        $msg->source->numeric(ERR_NEEDMOREPARAMS => $msg->command);
        return $PARAM_BAD;
    }

    foreach my $_t (@parameters) {
        $match_i++;

        # so basically the dash (-) means that this will not be
        # counted in the required parameters AND that it does
        # not actually have a real parameter associated with it.
        # if it does use a real parameter, DO NOT USE THIS!
        # use (opt) instead if that is the case.
        
        # is this a fake (ignored) matcher?
        my ($type, $fake) = $_t;
        if ($type =~ s/^-//) { $fake = 1  }
        else                 { $param_i++ }

        # split into a type and possibly an identifier.
        my $param = $params[$param_i];
        
        # if this is not a fake matcher, and if there is no parameter,
        # we should skip this. well, we should be done with the rest, too.
        last if !$fake && !defined $param;
        
        # any string.
        if ($type eq '*' || $type eq 'any') {
            push @final, $param;
        }
        
        # rest of the arguments as a list.
        elsif ($type eq '@rest' || $type eq '...') {
            push @final, @params[$param_i..$#params];
        }
        
        # rest of arguments, space-separated.
        elsif ($type eq ':rest') {
            push @final, join ' ', @params[$param_i..$#params];
        }
        
        # code-implemented type.
        elsif (my $param_code = __PACKAGE__->can("_param_$type")) {
            my $res = $param_code->($msg, $param, \@final, $match_attr[$match_i]);
            return $PARAM_BAD if $res && $res eq $PARAM_BAD;
        }
        
        # unknown type.
        else {
            $mod->_log("unknown parameter type $type!");
            return $PARAM_BAD;
        }

    }
    return @final;
}

# -message: inserts the message object.
sub _param_message {
    my ($msg, $param, $params, $opts) = @_;
    push @$params, $msg;
}

# -data: inserts the raw line of data.
sub _param_data {
    my ($msg, $param, $params, $opts) = @_;
    push @$params, $msg->{data};
}

# -command: inserts the command name.
sub _param_command {
    my ($msg, $param, $params, $opts) = @_;
    push @$params, $msg->{command};
}

# -oper: checks if oper flags are present.
sub _param_oper {
    my ($msg, $param, $params, $opts) = @_;
    foreach my $flag (keys %$opts) {
        next if $msg->source->has_flag($msg);
        $msg->source->numeric(ERR_NOPRIVILEGES => $flag);
        return $PARAM_BAD;
    }
}

# server: match a server name.
sub _param_server {
    my ($msg, $param, $params, $opts) = @_;
    my $server = $pool->lookup_server_name($param);

    # not found, send no such server.
    if (!$server) {
        $msg->source->numeric(ERR_NOSUCHSERVER => $param);
        return $PARAM_BAD;
    }

    push @$params, $server;
}

# user: match a nickname.
sub _param_user {
    my ($msg, $param, $params, $opts) = @_;
    my $nickname = (split ',', $param)[0];
    my $user = $pool->lookup_user_nick($nickname);

    # not found, send no such nick.
    if (!$user) {
        $msg->source->numeric(ERR_NOSUCHNICK => $nickname);
        return $PARAM_BAD;
    }

    push @$params, $user;
}

# channel: match a channel name.
sub _param_channel {
    my ($msg, $param, $params, $opts) = @_;
    my $chaname = (split ',', $param)[0];
    my $channel = $pool->lookup_channel($chaname);
    
    # not found, send no such channel.
    if (!$channel) {
        $msg->source->numeric(ERR_NOSUCHCHANNEL => $chaname);
        return $PARAM_BAD;
    }
    
    # if 'inchan' attribute, the requesting user must be in the channel.
    if ($opts->{inchan} && !$channel->has_user($msg->source)) {
        $msg->source->numeric(ERR_NOTONCHANNEL => $channel->name);
        return $PARAM_BAD;
    }
    
    push @$params, $channel;
}



$mod