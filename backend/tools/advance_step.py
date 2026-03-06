"""Tool: signal the frontend to advance to the next wizard step."""


async def advance_step() -> dict:
    """Signal the frontend to advance to the next step in the wizard.
    Call this when the user says they're ready for the next step."""
    return {"action": "advance_step"}
