# Contract gathering

The yardstick for someone else's PR is **what the work itself promised**, not your taste. Gather that promise first, write it down, and only then read the code. Reviewing your own change, the contract has to be reconstructed from an issue and a diff. Here the PR body usually exists and is the single strongest source: the tags in the output come straight out of it.

**Order matters.** Freeze the contract in a scratch file **before** reading the diff. Once the change is in your head you will unconsciously read the contract as a description of what was done, and every gap disappears.

## Step 0: Get the whole tree without touching the user's checkout

Accurate review needs the whole repository, not the diff hunks: population enumeration, `git blame`, sibling conventions and premise verification all read files the PR never touched. Fetching the repo locally is expected. Mutating the user's working copy is not.

```bash
PR=1629
REPO=CUBRID/cubrid-testcases-private          # from the PR URL, or `gh repo view --json nameWithOwner`
WORK="$SCRATCH/pr-review/$PR"                 # session scratchpad
mkdir -p "$WORK"
```

**If the repo is already cloned locally** (`REPO_DIR`), add a namespaced ref and a detached worktree:

```bash
git -C "$REPO_DIR" fetch origin "pull/$PR/head:refs/pr-review/$PR"
git -C "$REPO_DIR" fetch origin "$BASE_BRANCH"
git -C "$REPO_DIR" worktree add --detach "$WORK/tree" "refs/pr-review/$PR"
```

Those two writes (one ref under `refs/pr-review/`, one worktree registration) are the only changes made to the user's repository, and both are removable. HEAD, the index, the working tree and every branch of theirs stay untouched.

- Never `gh pr checkout`. Never `git checkout` / `git switch` / `git stash` in their repo.
- Never write into `refs/heads/*` or `refs/remotes/origin/*`.
- Cleanup when the user says the review is done: `git -C "$REPO_DIR" worktree remove "$WORK/tree"` then `git -C "$REPO_DIR" update-ref -d "refs/pr-review/$PR"`.

**If the repo is not cloned**, clone into the scratch cache and do the same there:

```bash
git clone --filter=blob:none "https://github.com/$REPO.git" "$CACHE/$(basename $REPO)"
```

Everything below (`git log`, `git blame`, `rg`, compiles) runs inside `$WORK/tree` or the cache clone.

## Source 1: the PR body (strongest)

```bash
gh pr view "$PR" --repo "$REPO" \
  --json number,title,url,author,body,baseRefName,headRefName,headRefOid,files,additions,deletions \
  > "$WORK/pr.json"
jq -r .body "$WORK/pr.json" > "$WORK/contract-body.md"
jq -r '.files[].path' "$WORK/pr.json" > "$WORK/changed-files.txt"
```

Read `contract-body.md` and pull out, verbatim, three kinds of clause. These are what the review is actually measured against:

1. **선언 규칙 (declared rules)**: a numbered conversion-rule list, a naming rule, an assertion style the author says they applied everywhere. Each numbered rule becomes one checkable line and one candidate tag.
2. **제외 목록 (exclusions)**: what the author says they deliberately left out. An exclusion with a stated reason is a decision, not a defect. An exclusion with no stated reason is a **질문**, not a defect.
3. **카운트/표 (counts and tables)**: "7 classes", "converted 12 of 15", a before/after table. A declared count is a **claim to be tested**, never a stop condition for your own enumeration.

`changed-files.txt` is also the denominator of the coverage line in the output. Every file in it is read in full. No sampling.

### Enumerate and diff

Any clause naming a set gets its population derived **from the source**, then diffed against what the PR covers. This holds whether the clause states a size ("7 classes") or not ("상속 클래스", "모든 구현체", "관련 테스트 전부").

```bash
rg -l 'extends AbstractFooTest' "$WORK/tree" | sort > "$WORK/population.txt"
comm -23 "$WORK/population.txt" <(sed "s|^|$WORK/tree/|" "$WORK/changed-files.txt" | sort)
```

Derive the population first. If you enumerate while holding the declared count, you stop the moment the numbers match and never see the eighth class.

For each uncovered member, **resolve the fixture's concrete type before writing the finding**: find the factory method that returns it and check whether the change already holds such an instance. "이미 그 객체를 들고 있으니 한 줄이면 됩니다" is a completely different request from "새 테스트를 하나 써주세요", and the difference decides whether the author acts on it.

## Source 2: the Jira issue (acceptance criteria)

Use the sibling helper. Do not re-implement it.

```bash
bash ~/.claude/skills/jira-fetch/assets/fetch_jira.sh -o "$WORK/jira" CBRD-1234
```

It reaches **publicly readable CUBRID projects only: CBRD, TOOLS, APIS**. The issue's acceptance criteria, when present, are the strongest contract after the PR body, and a gap against them is tagged from their own wording (for example `[스펙 갭]`).

**CUBRIDQA is not reachable**: the helper returns HTTP 401. When the PR references a CUBRIDQA key:

> CUBRIDQA-1234는 공개 프로젝트가 아니라 자동으로 못 가져옵니다(401). 이슈 본문(특히 완료 조건)을 붙여넣어 주시면 그 기준으로 보겠습니다. 없이 진행하면 "이 PR이 무엇을 하기로 했는지"를 PR 본문만으로 추정하게 되어, 스펙 갭은 못 잡습니다.

Ask, and wait. Never review silently against no acceptance criteria while a key exists: findings derived from a guessed contract are exactly the ones that come back as 부당. If the user declines to paste, record it as 계약 결손 in the output header and proceed at reduced confidence.

Atlassian Cloud (Hibernate HHH) is not supported by this helper. Fetch such an issue with WebFetch, or ask the user.

## Source 3: commit messages on the PR branch

```bash
BASE=$(git -C "$WORK/tree" merge-base "origin/$BASE_BRANCH" HEAD)
git -C "$WORK/tree" log --no-merges --format='%h%n%s%n%b%n---' "$BASE..HEAD"
```

Commit messages carry intent the body dropped, and they are where a "why it is that way" answer often already exists. This is also the input to move **8 (name versus behaviour)** at commit granularity: read the subject as a claim and the commit's diff as the evidence.

## Source 4: linked PRs and issues the body references

Every `#123`, every issue key, every "follows up on ..." in the body:

```bash
gh pr view 1607 --repo "$REPO" --json title,body,files
gh pr diff 1607 --repo "$REPO"
```

Prior PRs on the same files establish the precedent the author is following. A pattern that looks wrong is often the pattern the previous PR agreed on, and calling it a defect without checking makes you the reviewer who did not read the history.

## Source 5: the history of the touched lines

This is the step that separates reviewing someone else's code from reviewing your own. **Before calling anything a defect, establish why it is that way.**

```bash
git -C "$WORK/tree" log --follow -p -- path/to/File.java
git -C "$WORK/tree" blame -L 120,160 "$BASE" -- path/to/File.java
```

Blame the lines **as they were before the PR** (at `$BASE`), so you see who wrote the original and why, not the PR author's own rewrite. If the history explains the shape, the finding either dissolves or turns into a question about whether that reason still holds.

## Source 6: the dependency artifact the build actually resolves

This is what makes premise verification possible at all. A symbol that exists in the newest upstream source may be absent from the jar checked into this repo, and a review that assumes otherwise asserts a defect that does not exist (or misses one that does).

```bash
rg -n 'compile|implementation|systemPath|<systemPath>|\.jar' build.gradle pom.xml build.xml 2>/dev/null
ls -l lib/*.jar
git -C "$WORK/tree" submodule status
```

Then verify in this order:

1. **Compile against the resolved artifact.** The compiler is the authority on what resolves.
2. **Run `javap` only on the symbols the compiler rejected**, to learn whether the symbol is missing, has a different signature, or is package-private.

```bash
javac -cp "lib/cubrid-jdbc.jar:." -d "$WORK/out" path/to/File.java
javap -classpath lib/cubrid-jdbc.jar -p com.example.Foo | rg 'someMethod'
```

`javap` on everything is noise. `javap` on a compiler error is an answer. Package-private is the specific trap that made one expert's suggested patch fail to compile, which is why patches in the output are labelled hints (see `output.md`).

## Source 7: conventions read off neighbouring files

Convention is checked at **two localities**, and they can disagree:

- **The whole tree**: how do the other files in this package or suite do the same thing?
- **The file itself**: does the new block match the rest of its own file? A block indented differently from its own file, or asserting differently from the 40 lines above it, is a real finding even when the tree has no global rule.

```bash
rg -n --context 3 'assertEquals\(' "$WORK/tree/src/test/java/<package>" | head -50
```

A convention that exists in neither locality is your taste, not a finding. Drop it.

## Write the contract ledger

Before opening the diff, write `$WORK/contract.md`:

| ID | 출처 | 계약 문구 (원문 인용) | 검증 방법 | 태그 후보 |
|----|------|----------------------|-----------|-----------|
| C1 | PR 본문 규칙 3 | "모든 assertEquals에 메시지 인자를 넣는다" | `rg 'assertEquals\('` 변경 파일 전수 | `[변환 규칙 3 미적용]` |
| C2 | PR 본문 제외 목록 | "SP 관련 3건은 제외" | 사유가 본문에 있는가 | `[제외 사유 미기재]` |
| C3 | CUBRIDQA-1234 완료 조건 2 | 사용자 붙여넣기 | 해당 동작을 검증하는 테스트 존재 여부 | `[스펙 갭]` |

Tags are **invented from this table**, not chosen from a fixed taxonomy, and they quote the contract's own vocabulary. A PR that declares numbered conversion rules yields `[변환 규칙 3 미적용]`. A PR whose issue lists acceptance criteria yields `[스펙 갭]`. A PR that declares neither yields neither tag, and that is information, not a gap in your tooling.

## When there is no contract

Say so, out loud, in the output. Do not quietly substitute your own standards for the author's promise.

- **Body exists but declares nothing** (one line, "fix test"): the contract is the commit messages plus the issue. Note it, and expect fewer contract-derived tags.
- **No body and no reachable issue**: state it in the output header, review against **the code's own internal consistency only** (does the name match the behaviour, does the file contradict itself, does the change break a caller in the tree), and mark the whole report as reduced confidence.
- In this state the balance shifts hard toward **질문**. Without a contract you cannot know what the author set out to do, so almost nothing qualifies as a defect against it. Findings that survive are the ones that need no contract at all: a compile break, a caller in the tree the change contradicts, an assertion that cannot hold.

```
계약 결손: PR 본문에 선언된 규칙이 없고, 연결된 이슈(CUBRIDQA-1234)는 접근이 안 됩니다(401).
코드 자체의 내부 정합성만 기준으로 봤습니다. 아래 지적은 그만큼 신뢰도가 낮습니다.
```
