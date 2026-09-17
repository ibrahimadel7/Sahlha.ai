"""Bounded declarative learning content. Never execute model-produced code."""
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator

VisualType = Literal['none', 'code_trace', 'loop_flow', 'condition_flow', 'variable_state',
    'number_line', 'equation_steps', 'coordinate_graph', 'labeled_diagram',
    'process_sequence', 'timeline', 'map_points', 'sentence_builder', 'word_highlight']


class VisualItem(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    label: str = Field(default='', max_length=500)
    detail: str = Field(default='', max_length=1000)
    value: float | None = None
    x: float | None = None
    y: float | None = None


class VisualSpec(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    title: str = Field(default='', max_length=200)
    items: list[VisualItem] = Field(default_factory=list, max_length=40)
    # Display-only source snippet; the renderer must not evaluate it.
    source_text: str = Field(default='', max_length=6000)


class Playground(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    interaction: Literal['none', 'step', 'select', 'order', 'highlight'] = 'none'
    prompt: str = Field(default='', max_length=500)
    choices: list[str] = Field(default_factory=list, max_length=20)


class LearningContent(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    core_idea: str = Field(min_length=1, max_length=6000)
    steps: list[str] = Field(default_factory=list, max_length=20)
    example: str = Field(default='', max_length=6000)
    common_mistake: str = Field(default='', max_length=2000)
    check_understanding: str = Field(default='', max_length=2000)
    visual_type: VisualType = 'none'
    visual_spec: VisualSpec = Field(default_factory=VisualSpec)
    playground: Playground = Field(default_factory=Playground)
    audio_script: str = Field(default='', max_length=12000)

    @model_validator(mode='after')
    def coherent_visual(self):
        if self.visual_type == 'none':
            self.visual_spec = VisualSpec()
            self.playground = Playground()
        elif not self.visual_spec.items and not self.visual_spec.source_text:
            raise ValueError('A visual needs grounded content')
        return self


def structured_fallback(skill, chunks, explanation):
    import re
    facts = [s.strip() for c in chunks for s in re.split(r'(?<=[.!?])\s+', c['text']) if s.strip()]
    example = next((s for s in facts if re.search(r'\bexample\b', s, re.I)), '')
    return LearningContent(core_idea=(facts[0] if facts else explanation)[:6000],
        steps=facts[1:5], example=example[:6000],
        common_mistake='; '.join(skill.get('misconceptions') or [])[:2000],
        check_understanding=skill.get('learning_objective') or f"Explain {skill['name']} using a source example.",
        audio_script=explanation[:12000]).model_dump()
