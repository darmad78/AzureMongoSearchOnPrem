#!/bin/bash
# flag-unused.sh
# Flags files/folders that are NOT used by deploy-phase 1–5

# List all files and folders in repo
all_files=$(find . -mindepth 1 -not -path "./.git/*")

# List of deploy scripts
deploy_scripts=("deploy-phase-1.sh" "deploy-phase-2.sh" "deploy-phase-3.sh" "deploy-phase-4.sh" "deploy-phase-5.sh")

# Collect all referenced files
referenced_files=()

for script in "${deploy_scripts[@]}"; do
    while IFS= read -r line; do
        # Extract files referenced in the script (basic approach)
        for word in $line; do
            # Skip commands and variables, keep paths ending with common extensions
            if [[ $word =~ \.sh$|\.yml$|\.yaml$|\.env$|\.json$|\.crt$|\.key$ ]]; then
                referenced_files+=("$word")
            fi
        done
    done < "$script"
done

# Add deploy scripts themselves
referenced_files+=("${deploy_scripts[@]}")

# Flag files not referenced
echo "The following files/folders are NOT referenced in deploy-phase 1–5 and could be considered for removal:"
for f in $all_files; do
    skip=false
    for r in "${referenced_files[@]}"; do
        if [[ "$f" == "$r" ]] || [[ "$f" == ./$r ]]; then
            skip=true
            break
        fi
    done
    $skip || echo "  $f"
done
