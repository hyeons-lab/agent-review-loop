s/^[[:space:]]*//
s/agent-review-loop-rounds/ROUNDS/g
s/agent-review-report-rounds/ROUNDS/g
s/pr-comments-rounds/ROUNDS/g
s/agent-review-loop-reap-err/REAPERR/g
s/agent-review-report-reap-err/REAPERR/g
s/pr-comments-reap-err/REAPERR/g
s/-name 'agent-review-loop\.\*'/-name "PATPER"/g
s/-name 'agent-review-report\.\*'/-name "PATPER"/g
s/-name 'pr-comments\.\*'/-name "PATPER"/g
s/-name 'agent-review-loop\*'/-name "PATTOP"/g
s/-name 'agent-review-report\*'/-name "PATTOP"/g
s/-name 'pr-comments\*'/-name "PATTOP"/g
