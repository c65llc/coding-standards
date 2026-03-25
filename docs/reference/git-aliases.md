---
title: "Git Aliases Reference"
---

# Git Aliases Reference

Git aliases provide shortcuts for common operations. Run `scripts/setup-git-aliases.sh` to install all aliases automatically.

## Core Workflow Aliases

* **`git co <branch>`** - Checkout a branch
* **`git cob <branch>`** - Create and checkout new branch (`checkout -b`)
* **`git kick "message"`** - Create empty commit (`commit --allow-empty -m`)
* **`git up`** - Fetch and rebase against origin/main
* **`git refresh-main`** - Reset local main branch to match origin/main (creates temp branch if on main, deletes local main, checks out origin/main, cleans up)
* **`git st`** - Status
* **`git br`** - List branches
* **`git cm "message"`** - Commit with message (`commit -m`)
* **`git ca`** - Amend last commit (`commit --amend`)
* **`git cane`** - Amend without editing message (`commit --amend --no-edit`)
* **`git unstage`** - Unstage files (`reset HEAD --`)
* **`git undo`** - Undo last commit, keep changes (`reset --soft HEAD^`)

## Log and History Aliases

* **`git last`** - Show last commit (`log -1 HEAD`)
* **`git lg`** - Pretty log graph (`log --oneline --decorate --graph --all`)
* **`git ll`** - Last 10 commits (`log --oneline --decorate -10`)
* **`git recent`** - Show reflog

## Diff Aliases

* **`git diffc`** - Show staged changes (`diff --cached`)
* **`git diffst`** - Show staged changes (alternative: `diff --staged`)
* **`git who`** - Show blame (`blame`)

## Branch Management Aliases

* **`git branches`** - List all branches (`branch -a`)
* **`git ls`** - List most recently edited branches in reverse chronological order (`branch --sort=-committerdate`)
* **`git brm`** - Delete branches that are gone from remote
* **`git cleanup`** - Clean up remote-tracking branches

## Pull/Push Aliases

* **`git pullr`** - Pull with rebase (`pull --rebase`)
* **`git pushf`** - Push with force-lease (`push --force-with-lease`)
* **`git pushu`** - Push and set upstream (`push -u origin HEAD`)

## Feature Branch Helpers

* **`git feat <name>`** - Create feature branch (`feature/<name>`)
* **`git fix <name>`** - Create fix branch (`fix/<name>`)
* **`git hotfix <name>`** - Create hotfix branch (`hotfix/<name>`)

## Stash Aliases

* **`git stashlist`** - List stashes (`stash list`)
* **`git stashpop`** - Pop latest stash (`stash pop`)
* **`git stashapply`** - Apply latest stash (`stash apply`)

## Convenience Aliases

* **`git aliases`** - List all configured aliases
* **`git amend`** - Amend last commit without editing (`commit --amend --no-edit`)
* **`git save`** - Stage all and commit with "WIP" message
* **`git wip`** - Stage all and commit with "WIP" message

## Automatic Setup

To automatically configure all aliases, run:

```bash
# From standards repository
./scripts/setup-git-aliases.sh

# Or as part of project setup
./.standards/scripts/setup-git-aliases.sh
```

The setup script will:

* Check for existing aliases and prompt before overwriting
* Configure all recommended aliases
* Provide feedback on what was configured

## Manual Configuration

If you prefer to configure aliases manually:

```bash
# Core aliases
git config --global alias.st status
git config --global alias.co checkout
git config --global alias.cob 'checkout -b'
git config --global alias.kick 'commit --allow-empty -m'
git config --global alias.up '!git fetch origin && git rebase origin/main'

# View all aliases
git config --global --get-regexp alias
```
