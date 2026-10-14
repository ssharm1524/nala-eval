# Sourced by the shell tools: loads eval/config.env and exports it to the Python tools.
# NALA_EVAL_CONFIG names another file. See config.example.env for every setting.
config_file=${NALA_EVAL_CONFIG:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.env}
[ -f "$config_file" ] || { echo "no $config_file; copy eval/config.example.env to it and fill it in" >&2; exit 1; }
set -a
# shellcheck disable=SC1090
. "$config_file"
set +a
NALA_SCRATCH_ROOT=${NALA_SCRATCH_ROOT:-$HOME/nala-eval-runs}
NALA_EVAL_GH_CONFIG=${NALA_EVAL_GH_CONFIG:-$HOME/.config/gh-nala-eval}
export NALA_SCRATCH_ROOT NALA_EVAL_GH_CONFIG
