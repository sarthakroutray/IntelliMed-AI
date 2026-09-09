"""
Lab report understanding pipeline (v2) — Stage 1 -> 2 -> 3 orchestration.

Stage 1 (ocr_stage):      OpenDataLoader extraction, structure + bounding boxes.
Stage 2 (slm_stage):      normalization into the fixed lab report schema.
Stage 3 (rule_engine):    deterministic flagging from the external rule table.

Constraint enforced by construction: only Stage 3 emits abnormal flags or
patterns. Every emitted pattern references the exact test values and their
source_bbox, so doctor-facing output is fully traceable.
"""

from lab_pipeline import ocr_stage, rule_engine, slm_stage

__all__ = ['run_lab_report_pipeline']


async def run_lab_report_pipeline(file_path: str) -> dict:
    """Run the full lab report understanding pipeline on a document.

    Returns an envelope containing all three stage outputs plus warnings and
    the rule table review status, so nothing downstream can present
    untraceable AI output.
    """
    stage1 = await ocr_stage.run_stage1(file_path)

    stage2, stage2_engine, stage2_warnings = slm_stage.run_stage2(stage1)

    rule_table = rule_engine.load_rule_table()
    stage3 = rule_engine.annotate(stage2, rule_table['rules'])

    return {
        'pipeline': 'lab-report-understanding/v2',
        'stage1': stage1,
        'stage2': stage2,
        'stage2_engine': stage2_engine,
        'stage3': stage3,
        'warnings': list(stage1.get('warnings') or []) + stage2_warnings,
        'rules_review_status': rule_table['review_status'],
    }
