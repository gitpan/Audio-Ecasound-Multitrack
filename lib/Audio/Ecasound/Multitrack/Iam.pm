package Audio::Ecasound::Multitrack;
our $VERSION = 1.0;

use vars qw(%iam_cmd);


map { $iam_cmd{$_}++ } split "\n", <<CMD;
st
cs
es
fs
st
run
debug
engine-status
engine-launch
engine-halt
cs-add
cs-remove
cs-list
cs-select
cs-selected
cs-index-select
cs-load
cs-save
cs-save-as
cs-edit
cs-is-valid
cs-connect
cs-disconnect
cs-connected
cs-rewind
cs-forward
cs-set-position
cs-set-position-samples
cs-get-position
cs-getpos
get-position
cs-get-position-samples
cs-get-length
get-length
cs-get-length-samples
get-length-samples
cs-set-length
cs-set-length-samples
cs-toggle-loop
cs-set-param
cs-set-audio-format
cs-status
status
st
cs-option
c-add
c-remove
c-list
c-select
c-index-select
c-select-all
c-select-add
c-deselect
c-selected
c-clear
c-rename
c-muting
c-mute
c-bypass
c-status
cs
ai-add
ao-add
ao-add-default
ai-describe
ao-describe
ai-select
ai-index-select
ai-selected
ao-selected
ai-attach
ao-attach
ai-remove
ao-remove
ai-forward
ai-rewind
ai-setpos
ai-set-position-samples
ai-getpos
ai-get-position
ao-getpos
ao-get-position
ai-get-position-samples
ao-get-position-samples
ai-get-length
ao-get-length
ai-get-length-samples
ao-get-length-samples
ai-get-format
ao-get-format
ai-wave-edit
ao-wave-edit
ai-list
ao-list
aio-register
aio-status
cop-add
cop-describe
cop-remove
cop-list
cop-select
cop-selected
cop-set
cop-status
copp-list
copp-select
copp-selected
copp-set
copp-get
cop-register
preset-register
ladspa-register
ctrl-add
ctrl-describe
ctrl-remove
ctrl-list
ctrl-select
ctrl-selected
ctrl-status
ctrl-register
ctrl-get-target
ctrlp-list
ctrlp-select
ctrlp-selected
ctrlp-get
ctrlp-set
int-cmd-list
int-log-history
int-output-mode-wellformed
int-set-float-to-string-precision
int-set-log-history-length
int-cmd-version-string
int-cmd-version-lib-current
int-cmd-version-lib-revision
int-cmd-version-lib-age
map-cop-list
map-preset-list
map-ladspa-list
map-ladspa-id-list
map-ctrl-list
dump-target
dump-status
dump-position
dump-length
dump-cs-status
dump-c-selected
dump-ai-selected
dump-ai-position
dump-ai-length
dump-ai-open-state
dump-ao-selected
dump-ao-position
dump-ao-length
dump-ao-open-state
dump-cop-value
CMD
#print keys %iam_cmd;
1;
