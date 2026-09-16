"""LangGraph teacher content pipeline (stateful, human-in-the-loop).

Kept deliberately narrow: only the teacher content workflow
(retrieve → extract → explain → generate → teacher gate → regenerate?)
runs as a graph. Everything else (FastAPI, OCR, RAG utils, CRUD, TTS/images,
deterministic assessment) stays ordinary Python — see PROJECT.md §4.
"""
from sahlha.app.workflow.graph import get_graph
from sahlha.app.workflow.state import MAX_REGENERATIONS, SahlhaWorkflowState, initial_state

__all__ = ["MAX_REGENERATIONS", "SahlhaWorkflowState", "get_graph", "initial_state"]
