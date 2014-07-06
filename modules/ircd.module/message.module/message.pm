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

our ($api, $mod, $pool, $me);
our $TRUE = '__TAG_TRUE__';

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
            ($got_command, $msg->{command}) = (1, uc $word);
            next WORD;
            
        }
        
        # sentinel-prefixed final parameter.
        # I would like to do this without splitting again...
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


sub command { shift->{command}          }
sub source  { shift->{source}           }
sub tags    { shift->{tags}             }
sub tag     { shift->{tags}{+shift}     }
sub params  { @{ shift->{params} }      }
sub param   { shift->{params}[shift]    }

sub source_nick  { ... }
sub source_ident { ... }
sub source_host  { ... }

$mod