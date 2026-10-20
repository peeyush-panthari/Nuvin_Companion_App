import pytest
from backend.app.modules.agent.langchain_agent import (
    GuardedLangChainRunner, ReminderActionInput, MemoryInspectInput, TriggerSOSInput, CircuitBreakerException
)

@pytest.mark.asyncio
async def test_langchain_anti_hallucination_schema_validation():
    """
    GUARDRAIL 1: Anti-Hallucination Tool Validation.
    Asserts that hallucinated arguments or invalid parameter structures are rejected.
    """
    # 1. Valid arguments -> PASS
    valid_args = {"title": "Blood Pressure Tablet", "schedule": "08:00 daily", "reminder_type": "medicine"}
    res = GuardedLangChainRunner.validate_action_payload("create_reminder", valid_args)
    assert res["title"] == "Blood Pressure Tablet"
    assert res["schedule"] == "08:00 daily"

    # 2. Medical dosage alteration hallucination -> BLOCKED
    invalid_med_args = {"title": "Double dose of heart medication", "schedule": "daily", "reminder_type": "medicine"}
    with pytest.raises(ValueError, match="Prohibited medical alteration"):
        GuardedLangChainRunner.validate_action_payload("create_reminder", invalid_med_args)

    # 3. Non-existent / hallucinated tool -> REJECTED
    with pytest.raises(ValueError, match="Unknown or hallucinated tool"):
        GuardedLangChainRunner.validate_action_payload("hallucinated_execute_command", {"command": "delete_all"})

    print("\n[GUARDRAIL PASSED] Anti-hallucination tool schema validation strictly active.")

@pytest.mark.asyncio
async def test_langchain_circuit_breaker_max_iterations():
    """
    GUARDRAIL 2: Circuit Breaker against uncontrolled retry storms.
    Asserts max_iterations is hard-capped at 2.
    """
    assert GuardedLangChainRunner.MAX_ITERATIONS == 2
    assert GuardedLangChainRunner.MAX_RETRIES == 1

    # Run guarded chain with user turn
    result = await GuardedLangChainRunner.run_guarded_chain(
        user_id="test-langchain-user",
        user_message="Hello, can you remind me to water plants tomorrow at 5 PM?",
        system_prompt="You are a helpful companion.",
        retrieved_memories=["User likes gardening."],
        locale="en-IN"
    )

    # Verify execution completed within max iterations (no infinite loop)
    assert result["iterations_used"] <= 2
    assert result["action_triggered"] == "create_reminder"
    assert result["open_ui_card"] is not None
    assert "payload_hash" in result["open_ui_card"]
    print(f"\n[GUARDRAIL PASSED] Chain executed in {result['iterations_used']} iteration (Capped at 2).")

@pytest.mark.asyncio
async def test_langchain_payload_hash_trust_plane_binding():
    """
    GUARDRAIL 3: Payload Hashing for Trust Plane Authorization.
    Asserts that every proposed action is bound to a deterministic SHA-256 payload hash.
    """
    payload = {"title": "Thyroid tablet", "schedule": "07:00 daily", "reminder_type": "medicine"}
    hash_one = GuardedLangChainRunner.compute_payload_hash("create_reminder", payload)
    hash_two = GuardedLangChainRunner.compute_payload_hash("create_reminder", payload)

    assert hash_one == hash_two
    assert len(hash_one) == 64
    print(f"\n[GUARDRAIL PASSED] Deterministic payload hash verified: {hash_one[:16]}...")
