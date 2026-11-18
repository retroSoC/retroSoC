.PHONY: agent-context agent-task-check agent-handoff agent-scope-check agent-preflight agent-deliver agent-coordinate agent-dag agent-lease agent-lease-release snapshot-check validation-gap-check worktree-registry agent-worktree-start fixture-plan fixture-restore fixture-doctor validation-plan documentation-check skill-eval-static skill-eval-smoke skill-replay engineering-metrics fixtures-plan fixtures-shard fixtures-verify incremental-shadow delivery-policy

agent-context:
	python3 $(ROOT_PATH)/scripts/agent_control.py context --root $(ROOT_PATH) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/agent-context.json)

agent-task-check:
	@test -n '$(TASK)' || { printf '%s\n' 'TASK=<task.json> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/agent_control.py task validate --root $(ROOT_PATH) --task $(TASK)

agent-handoff:
	@test -n '$(TASK)' || { printf '%s\n' 'TASK=<task.json> is required'; exit 2; }
	@test -n '$(NEXT)' || { printf '%s\n' 'NEXT=<next action> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/agent_control.py task handoff --root $(ROOT_PATH) --task $(TASK) \
	  --next "$(NEXT)" --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/agent-handoff.json) \
	  $(if $(MARKDOWN),--markdown $(MARKDOWN))

validation-gap-check:
	python3 $(ROOT_PATH)/scripts/validation_gaps.py --root $(ROOT_PATH) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/validation-gaps.json)

worktree-registry:
	python3 $(ROOT_PATH)/scripts/worktree_registry.py --root $(ROOT_PATH) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(ROOT_PATH)/build/agent-worktrees/registry.json) \
	  $(if $(EXECUTE),--execute)

agent-worktree-start:
	@test -n '$(TASK)' || { printf '%s\n' 'TASK=<task.json> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/worktree_bootstrap.py --root $(ROOT_PATH) --task $(TASK) \
	  $(if $(BRANCH),--branch $(BRANCH)) $(foreach source,$(SOURCES),--source $(source)) \
	  $(foreach archive,$(ARCHIVES),--archive $(archive)) \
	  $(if $(CREATE),--create) $(if $(ALLOW_NETWORK),--allow-network) \
	  $(if $(EXECUTE),--execute) $(if $(OUTPUT),--output $(OUTPUT))

fixture-plan:
	@test -n '$(REFERENCE_ROOT)' || { printf '%s\n' 'REFERENCE_ROOT=<validated local worktree> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/fixture_control.py plan --root $(ROOT_PATH) \
	  --reference-root $(REFERENCE_ROOT) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/fixture-plan.json)

fixture-restore:
	@test -n '$(REFERENCE_ROOT)' || { printf '%s\n' 'REFERENCE_ROOT=<validated local worktree> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/fixture_control.py restore --root $(ROOT_PATH) \
	  --reference-root $(REFERENCE_ROOT) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/fixture-restore.json)

fixture-doctor:
	python3 $(ROOT_PATH)/scripts/fixture_control.py doctor --root $(ROOT_PATH) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/fixture-doctor.json)

agent-scope-check:
	@test -n '$(TASK)' || { printf '%s\n' 'TASK=<task.json> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/agent_control.py scope-check --root $(ROOT_PATH) --task $(TASK) \
	  $(if $(BASE),--base $(BASE)) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/agent-scope-check.json)

agent-preflight:
	@test -n '$(TASK)' || { printf '%s\n' 'TASK=<task.json> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/agent_control.py preflight --root $(ROOT_PATH) --task $(TASK) \
	  $(if $(BASE),--base $(BASE)) --head $(if $(HEAD),$(HEAD),HEAD) \
	  --repository $(if $(REPOSITORY),$(REPOSITORY),retroSoC/retroSoC) \
	  --base-branch $(if $(BASE_BRANCH),$(BASE_BRANCH),dev) \
	  $(if $(PR),--pr $(PR)) $(if $(ONLINE),--online) \
	  $(if $(filter 0,$(MERGE_CHECK)),--no-merge-check,--merge-check) \
	  --merge-ref $(if $(MERGE_REF),$(MERGE_REF),origin/dev) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/agent-preflight.json)

agent-deliver:
	@test -n '$(PR)' || { printf '%s\n' 'PR=<number> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/pr_delivery.py --root $(ROOT_PATH) \
	  --pr $(PR) --repository $(if $(REPOSITORY),$(REPOSITORY),retroSoC/retroSoC) \
	  --interval $(if $(INTERVAL),$(INTERVAL),60) \
	  $(if $(WATCH),--watch) $(if $(PREFLIGHT),--preflight-only) \
	  $(if $(RECONCILE),--reconcile-only) $(if $(RESUME),--resume) \
	  $(if $(RESUME_REASON),--resume-reason "$(RESUME_REASON)") \
	  $(if $(OUTPUT),--output $(OUTPUT))

agent-coordinate:
	@test -n '$(PRS)' || { printf '%s\n' 'PRS=<number>... is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/delivery_controller.py --root $(ROOT_PATH) \
	  $(foreach pr,$(PRS),--pr $(pr)) --repository $(if $(REPOSITORY),$(REPOSITORY),retroSoC/retroSoC) \
	  --interval $(if $(INTERVAL),$(INTERVAL),60) \
	  $(if $(DELIVERY_DIR),--delivery-dir $(DELIVERY_DIR)) $(if $(WATCH),--watch) \
	  $(if $(OUTPUT),--output $(OUTPUT))

agent-dag:
	@test -n '$(GRAPH)' || { printf '%s\n' 'GRAPH=<graph.json> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/agent_dag.py --root $(ROOT_PATH) plan --graph $(GRAPH) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/agent-dag.json)

agent-lease:
	@test -n '$(GRAPH)' || { printf '%s\n' 'GRAPH=<graph.json> is required'; exit 2; }
	@test -n '$(TASK)' || { printf '%s\n' 'TASK=<task-id> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/agent_dag.py --root $(ROOT_PATH) acquire \
	  --graph $(GRAPH) --task $(TASK) $(if $(OWNER),--owner $(OWNER)) \
	  $(if $(EXECUTE),--execute) $(if $(OUTPUT),--output $(OUTPUT))

agent-lease-release:
	@test -n '$(GRAPH)' || { printf '%s\n' 'GRAPH=<graph.json> is required'; exit 2; }
	@test -n '$(TASK)' || { printf '%s\n' 'TASK=<task-id> is required'; exit 2; }
	@test -n '$(LEASE_ID)' || { printf '%s\n' 'LEASE_ID=<id> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/agent_dag.py --root $(ROOT_PATH) release \
	  --graph $(GRAPH) --task $(TASK) --lease-id $(LEASE_ID) \
	  $(if $(EXECUTE),--execute) $(if $(OUTPUT),--output $(OUTPUT))

snapshot-check:
	python3 $(ROOT_PATH)/scripts/agent_control.py snapshot --root $(ROOT_PATH) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/reviewed-source-snapshot.json)

validation-plan:
	python3 $(ROOT_PATH)/scripts/agent_control.py plan --root $(ROOT_PATH) \
	  --event $(if $(EVENT),$(EVENT),local) --mode $(if $(MODE),$(MODE),auto) \
	  $(if $(BASE),--base $(BASE)) $(if $(FILES),--files $(FILES)) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/validation-plan.json)

documentation-check:
	python3 $(ROOT_PATH)/scripts/agent_control.py docs --root $(ROOT_PATH) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/documentation-check.json)

skill-eval-static:
	python3 $(ROOT_PATH)/scripts/skill_eval.py validate --root $(ROOT_PATH) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/skill-eval-static.json)

skill-eval-smoke:
	python3 $(ROOT_PATH)/scripts/skill_eval.py run --root $(ROOT_PATH) --smoke \
	  $(if $(RUNNER),--runner $(RUNNER)) $(if $(MODEL),--model $(MODEL)) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/agent-evals/smoke)

skill-replay:
	@test -n '$(TRACES)' || { printf '%s\n' 'TRACES=<directory> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/skill_eval.py replay --root $(ROOT_PATH) \
	  --trace-root $(TRACES) $(if $(SKILL),--skill $(SKILL)) \
	  $(if $(CASE),--case $(CASE)) $(if $(SMOKE),--smoke) $(if $(LATEST),--latest-per-case) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/agent-evals/replay.json)

engineering-metrics:
	python3 $(ROOT_PATH)/scripts/engineering_metrics.py collect \
	  --repository $(if $(REPOSITORY),$(REPOSITORY),retroSoC/retroSoC) \
	  --limit $(if $(LIMIT),$(LIMIT),30) \
	  $(if $(DELIVERY_DIR),--delivery-dir $(DELIVERY_DIR)) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/engineering-metrics.json)

delivery-policy:
	python3 $(ROOT_PATH)/scripts/delivery_policy.py --root $(ROOT_PATH) \
	  --repository $(if $(REPOSITORY),$(REPOSITORY),retroSoC/retroSoC) \
	  $(if $(OFFLINE),--offline) $(if $(PULLS),--pulls $(PULLS)) \
	  $(if $(RUNS),--runs $(RUNS)) $(if $(SAMPLES),--samples $(SAMPLES)) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(VARIANT_ROOT)/meta/delivery-policy.json)

fixtures-plan:
	python3 $(ROOT_PATH)/scripts/pytest_shards.py plan --root $(ROOT_PATH) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(ROOT_PATH)/build/pytest/shards/plan.json)

fixtures-shard:
	@test -n '$(SHARD)' || { printf '%s\n' 'SHARD=<index> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/pytest_shards.py run --root $(ROOT_PATH) \
	  --shard $(SHARD) --output $(if $(OUTPUT),$(OUTPUT),$(ROOT_PATH)/build/pytest/shard-$(SHARD))

fixtures-verify:
	@test -n '$(SHARD_DIRS)' || { printf '%s\n' 'SHARD_DIRS=<directories> is required'; exit 2; }
	python3 $(ROOT_PATH)/scripts/pytest_shards.py verify --root $(ROOT_PATH) \
	  $(foreach directory,$(SHARD_DIRS),--shard-dir $(directory)) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(ROOT_PATH)/build/pytest/fan-in/summary.json)

incremental-shadow:
	python3 $(ROOT_PATH)/scripts/incremental_ci.py --root $(ROOT_PATH) \
	  --base $(if $(BASE),$(BASE),origin/dev) --head $(if $(HEAD),$(HEAD),HEAD) \
	  --event $(if $(EVENT),$(EVENT),pull_request) \
	  $(if $(EVIDENCE),--evidence $(EVIDENCE)) $(if $(SOURCE_RUN),--source-run $(SOURCE_RUN)) \
	  $(if $(EXECUTE),--execute) \
	  --output $(if $(OUTPUT),$(OUTPUT),$(ROOT_PATH)/build/incremental-ci/shadow.json)