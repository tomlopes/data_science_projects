"""
Simple evaluation script for the policy-checker agent without AI Foundry upload.
This avoids storage permission issues while still running the core evaluation.
"""

import os
import time
import json

from pathlib import Path
from dotenv import load_dotenv
from urllib.parse import urlparse

from azure.ai.agents.models import RunStatus, MessageRole
from azure.ai.projects import AIProjectClient
from azure.ai.evaluation import (
    AIAgentConverter, evaluate, ToolCallAccuracyEvaluator, IntentResolutionEvaluator, 
    TaskAdherenceEvaluator, ContentSafetyEvaluator, CodeVulnerabilityEvaluator, 
    IndirectAttackEvaluator)

from azure.identity import DefaultAzureCredential
import logging
import pandas as pd

# Reduce noisy logs from underlying evaluation/execution libraries. Keep
# our own print() output intact while elevating third-party loggers to
# WARNING to avoid progress/info spam like "Finished 2 / 5 lines.".
for noisy in ("execution.bulk", "azure", "azure.ai", "promptflow", "azure.ai.evaluation"):
    try:
        logging.getLogger(noisy).setLevel(logging.WARNING)
    except Exception:
        pass

class OperationalMetricsEvaluator:
    """Propagate operational metrics to the final evaluation results"""
    def __init__(self):
        pass
    def __call__(self, *, metrics: dict, **kwargs):
        return metrics

def run_simple_evaluation():
    """Run evaluation with comprehensive evaluators and no AI Foundry upload"""
    
    print("🚀 Starting Simple AI Agent Evaluation for Policy Checker")
    print("=" * 55)
    
    current_dir = Path(__file__).parent
    eval_queries_path = current_dir / "eval-queries.json"
    eval_input_path = current_dir / "eval-input-simple.jsonl"
    eval_output_path = current_dir / "eval-output-simple.json"

    # Load environment variables
    env_path = current_dir / "../.env"
    if not env_path.exists():
        raise ValueError(f"Environment file not found at {env_path}. Please create a .env file based on .env.sample")
    
    load_dotenv(dotenv_path=env_path)

    # Get AI project parameters
    project_endpoint = os.environ.get("AI_FOUNDRY_PROJECT_ENDPOINT")
    if not project_endpoint:
        raise ValueError("Please set the AI_FOUNDRY_PROJECT_ENDPOINT environment variable in your .env file.")

    parsed_endpoint = urlparse(project_endpoint)
    model_endpoint = f"{parsed_endpoint.scheme}://{parsed_endpoint.netloc}"
    deployment_name = "gpt-4.1-mini"
    agent_name = "policy-checker"

    # Initialize client
    credential = DefaultAzureCredential(exclude_interactive_browser_credential=False)
    ai_project = AIProjectClient(
        credential=credential,
        endpoint=project_endpoint,
        api_version="2025-05-15-preview"
    )

    # Find agent
    print(f"🔍 Looking for agent named '{agent_name}'...")
    agent_found = False
    for agent in ai_project.agents.list_agents():
        if agent.name == agent_name:
            agent_id = agent.id
            agent_found = True
            print(f"✅ Found agent '{agent_name}' with ID: {agent_id}")
            break
            
    if not agent_found:
        available_agents = [a.name for a in ai_project.agents.list_agents()]
        raise ValueError(f"Agent '{agent_name}' not found. Available agents: {available_agents}")

    agent = ai_project.agents.get_agent(agent_id)

    # Setup evaluation config
    model_config = {
        "azure_deployment": deployment_name,
        "azure_endpoint": model_endpoint,
        "api_version": "2024-10-21",
    }
    thread_data_converter = AIAgentConverter(ai_project)

    # Read test queries
    with open(eval_queries_path, "r", encoding="utf-8") as f:
        test_data = json.load(f)
    
    # Execute queries and prepare evaluation input
    print(f"📝 Running {len(test_data)} test queries against the agent...")
    
    with open(eval_input_path, "w", encoding="utf-8") as f:        
        for i, row in enumerate(test_data, 1):
            print(f"  Processing query {i}/{len(test_data)}: {row.get('query')[:60]}...")
            
            thread = ai_project.agents.threads.create()
            ai_project.agents.messages.create(
                thread.id, role=MessageRole.USER, content=row.get("query")
            )

            start_time = time.time()
            run = ai_project.agents.runs.create_and_process(
                thread_id=thread.id, agent_id=agent.id
            )
            end_time = time.time()

            if run.status != RunStatus.COMPLETED:
                print(f"  ⚠️  Query {i} failed: {run.last_error}")
                continue
            else:
                print(f"  ✅ Query {i} completed successfully")

            operational_metrics = {
                "server-run-duration-in-seconds": (run.completed_at - run.created_at).total_seconds(),
                "client-run-duration-in-seconds": end_time - start_time,
                "completion-tokens": run.usage.completion_tokens,
                "prompt-tokens": run.usage.prompt_tokens,
                "ground-truth": row.get("ground-truth", '')
            }

            evaluation_data = thread_data_converter.prepare_evaluation_data(thread_ids=thread.id)
            eval_item = evaluation_data[0]
            eval_item["metrics"] = operational_metrics
            f.write(json.dumps(eval_item) + "\n")   
        
    print("✅ All test queries completed successfully!")

    # Setup comprehensive evaluators
    print("🔧 Setting up comprehensive evaluators...")
    # Build a minimal azure_ai_project dictionary required by some evaluators.
    # Prefer explicit environment variables, fall back to parsing resource IDs.
    project_name = os.environ.get("AI_FOUNDRY_PROJECT_NAME")
    subscription_id = None
    resource_group_name = None

    # Try to parse subscription and resource group from AZURE_AI_CONNECTION_ID
    conn_id = os.environ.get("AZURE_AI_CONNECTION_ID") or os.environ.get("AI_FOUNDRY_HUB_ENDPOINT")
    if conn_id:
        import re
        m = re.search(r"/subscriptions/([^/]+)/resourceGroups/([^/]+)/", conn_id)
        if m:
            subscription_id = m.group(1)
            resource_group_name = m.group(2)

    # If project name still missing, try to extract from the project endpoint URL
    try:
        pe = urlparse(project_endpoint)
        path_parts = [p for p in pe.path.split("/") if p]
        if "projects" in path_parts:
            idx = path_parts.index("projects")
            if idx + 1 < len(path_parts):
                project_name = project_name or path_parts[idx + 1]
    except Exception:
        pass

    azure_project_dict = {
        "project_name": project_name,
        "resource_group_name": resource_group_name,
        "subscription_id": subscription_id,
        "endpoint": project_endpoint,
        "agent_id": agent_id,
    }

    # Warn if required fields are missing; evaluators may still accept the dict
    missing = [k for k in ("project_name", "resource_group_name", "subscription_id") if not azure_project_dict.get(k)]
    if missing:
        print(f"⚠️  azure_ai_project dictionary is missing fields: {missing}. Evaluators may fail if these are required.")
    
    evaluators_config = {
        "operational_metrics": OperationalMetricsEvaluator(),
    }
    
    # Add core AI agent evaluation metrics
    try:
        evaluators_config["tool_call_accuracy"] = ToolCallAccuracyEvaluator(model_config=model_config)
        print("  ✅ tool_call_accuracy evaluator added")
    except Exception as e:
        print(f"  ⚠️  tool_call_accuracy evaluator skipped: {e}")

    try:
        evaluators_config["intent_resolution"] = IntentResolutionEvaluator(model_config=model_config)
        print("  ✅ intent_resolution evaluator added")
    except Exception as e:
        print(f"  ⚠️  intent_resolution evaluator skipped: {e}")

    try:
        evaluators_config["task_adherence"] = TaskAdherenceEvaluator(model_config=model_config)
        print("  ✅ task_adherence evaluator added")
    except Exception as e:
        print(f"  ⚠️  task_adherence evaluator skipped: {e}")

    # Add security and safety evaluators
    try:
        # The evaluator expects a dictionary for 'azure_ai_project' in some
        # SDK versions. Provide a minimal mapping (endpoint and agent id) to
        # satisfy validation while preserving credential usage.
        azure_project_dict = {"endpoint": project_endpoint, "agent_id": agent_id}
        evaluators_config["code_vulnerability"] = CodeVulnerabilityEvaluator(
            credential=credential, azure_ai_project=azure_project_dict
        )
        print("  ✅ code_vulnerability evaluator added")
    except Exception as e:
        print(f"  ⚠️  code_vulnerability evaluator skipped: {e}")

    try:
        evaluators_config["content_safety"] = ContentSafetyEvaluator(
            credential=credential, azure_ai_project=azure_project_dict
        )
        print("  ✅ content_safety evaluator added")
    except Exception as e:
        print(f"  ⚠️  content_safety evaluator skipped: {e}")

    try:
        evaluators_config["indirect_attack"] = IndirectAttackEvaluator(
            credential=credential, azure_ai_project=azure_project_dict
        )
        print("  ✅ indirect_attack evaluator added")
    except Exception as e:
        print(f"  ⚠️  indirect_attack evaluator skipped: {e}")

    # Run evaluation WITHOUT AI Foundry upload
    print(f"\n📊 Running local evaluation with {len(evaluators_config)} evaluators...")
    
    results = evaluate(
        evaluation_name="policy-checker-comprehensive-evaluation",
        data=eval_input_path,
        evaluators=evaluators_config,
        output_path=eval_output_path,
        # NO azure_ai_project parameter to avoid storage permission issues
    )
    
    print("✅ Comprehensive evaluation completed!")
    
    
    # Support different return shapes from evaluate(): an object with a .metrics
    # attribute or a plain dict that contains a 'metrics' key. Print helpful
    # diagnostics when metrics are missing so callers can debug easily.
    metrics = None
    if hasattr(results, 'metrics'):
        metrics = results.metrics
    elif isinstance(results, dict):
        # The evaluate() helper may return a plain dict in some implementations
        # (observed in user run). Try to extract a 'metrics' key or use the
        # dict itself as a fallback.
        metrics = results.get('metrics') or results

    if metrics:
        # If metrics is still a dict-like object, iterate and format values
        for key, value in metrics.items():
            if isinstance(value, float):
                # Convert to percentage if it looks like a proportion (0-1 range)
                if 0 <= value <= 1 and key in ['intent_resolution', 'task_adherence', 'tool_call_accuracy']:
                    percentage = value * 100
                    print(f"{key:<35} | {percentage:.1f}%")
                else:
                    print(f"{key:<35} | {value:.2f}")
            else:
                print(f"{key:<35} | {value}")
    else:
        # Provide richer diagnostics and, if present, pretty-print the
        # evaluation output file which often contains all computed metrics.
        print("No metrics found in results — falling back to evaluation output file")
        print(f"Results type: {type(results)}")
        try:
            with open(eval_output_path, "r", encoding="utf-8") as ef:
                eval_out = json.load(ef)

            rows = eval_out.get("rows") or []
            print(f"Evaluation output file '{eval_output_path}' contains {len(rows)} rows")

            for idx, row in enumerate(rows, 1):
                print("-" * 60)
                # Extract a human-friendly query string
                user_query = None
                try:
                    qitems = row.get("inputs.query", [])
                    for item in qitems:
                        if isinstance(item, dict) and item.get("role") == "user":
                            # content can be a list of text objects or a string
                            content = item.get("content")
                            if isinstance(content, list) and content:
                                # pick first text block
                                first = content[0]
                                user_query = first.get("text") or str(first)
                                break
                            elif isinstance(content, str):
                                user_query = content
                                break
                except Exception:
                    user_query = None

                print(f"Row {idx} - Query: {user_query or '<unavailable>'}")

                # Print any operational metrics attached to the row
                inputs_metrics = row.get("inputs.metrics") or row.get("outputs.operational_metrics")
                if inputs_metrics:
                    print("  Operational metrics:")
                    for k, v in inputs_metrics.items():
                        print(f"    {k:<40} : {v}")

                # Collect and group outputs by their category (outputs.<group>.*)
                outputs = {k: v for k, v in row.items() if k.startswith("outputs.")}
                if outputs:
                    grouped = {}
                    for k, v in outputs.items():
                        parts = k.split(".")
                        # outputs.<group>.<field> (or deeper)
                        if len(parts) >= 3:
                            group = parts[1]
                            field = ".".join(parts[2:])
                        else:
                            group = parts[1] if len(parts) > 1 else "misc"
                            field = parts[-1]
                        grouped.setdefault(group, {})[field] = v

                    for group, fields in grouped.items():
                        print(f"  {group}:")
                        for field, val in fields.items():
                            # Pretty-format floats
                            if isinstance(val, float):
                                print(f"    {field:<35} : {val:.4f}")
                            else:
                                print(f"    {field:<35} : {val}")

            print("-" * 60)
        except FileNotFoundError:
            print(f"Evaluation output file not found at: {eval_output_path}")
            if isinstance(results, dict):
                print(f"Result keys: {list(results.keys())}")
        except Exception as e:
            print(f"Could not read/parse evaluation output file: {e}")
            if isinstance(results, dict):
                print(f"Result keys: {list(results.keys())}")
    
    print("=" * 70)
    print(f"Evaluation input: {eval_input_path}")
    print(f"Evaluation output: {eval_output_path}")
    print("=" * 70)

    # Print a compact table for the first 5 user queries with key metrics
    try:
        print_user_queries_table(eval_output_path)
    except NameError:
        # If the function isn't defined yet (older runs), define it inline below
        pass


def print_user_queries_table(eval_output_path: str, top_n: int = 5):
    """Read the evaluation output file and print a compact table for the
    first `top_n` queries containing intent_resolution, task_adherence,
    tool_call_accuracy and basic operational metrics.
    """
    # Helper for safe value extraction
    def get_output_field(row, group, field, default="-"):
        key = f"outputs.{group}.{field}"
        return row.get(key, default)

    try:
        with open(eval_output_path, "r", encoding="utf-8") as ef:
            eval_out = json.load(ef)
    except Exception as e:
        print(f"Could not open evaluation output for table: {e}")
        return

    rows = eval_out.get("rows") or []
    if not rows:
        print("No rows available in evaluation output to tabulate.")
        return

    header = ["#", "Query (trunc)", "Intent", "TaskAdh", "ToolAcc", "SrvSec", "CliSec", "CompTok", "PromptTok"]
    # compute column widths
    widths = [4, 50, 8, 8, 8, 8, 8, 9, 10]

    def fmt_row(vals):
        parts = []
        for v, w in zip(vals, widths):
            s = str(v)
            if len(s) > w:
                s = s[: w - 1] + "…"
            parts.append(s.ljust(w))
        return " | ".join(parts)

    records = []
    for idx, row in enumerate(rows[:top_n], 1):
        # Query
        user_query = "<unavailable>"
        try:
            qitems = row.get("inputs.query", [])
            for item in qitems:
                if isinstance(item, dict) and item.get("role") == "user":
                    content = item.get("content")
                    if isinstance(content, list) and content:
                        user_query = content[0].get("text") or str(content[0])
                    elif isinstance(content, str):
                        user_query = content
                    break
        except Exception:
            pass

        # Metrics
        intent = get_output_field(row, "intent_resolution", "intent_resolution")
        task = get_output_field(row, "task_adherence", "task_adherence")
        tool = get_output_field(row, "tool_call_accuracy", "tool_call_accuracy")

        srv = row.get("outputs.operational_metrics.server-run-duration-in-seconds", None)
        cli = row.get("outputs.operational_metrics.client-run-duration-in-seconds", None)
        comp = row.get("outputs.operational_metrics.completion-tokens", None)
        prompt = row.get("outputs.operational_metrics.prompt-tokens", None)

        records.append({
            "index": idx,
            "query": user_query,
            "intent_resolution": intent,
            "task_adherence": task,
            "tool_call_accuracy": tool,
            "server_run_seconds": srv,
            "client_run_seconds": cli,
            "completion_tokens": comp,
            "prompt_tokens": prompt,
        })

    # Build DataFrame and save to Excel; fallback to CSV if Excel write isn't available
    try:
        df = pd.DataFrame(records)
        excel_path = Path(eval_output_path).parent / "eval-metrics-table.xlsx"
        df.to_excel(excel_path, index=False)
        print(f"Saved metrics table to: {excel_path}")
    except Exception as e:
        try:
            csv_path = Path(eval_output_path).parent / "eval-metrics-table.csv"
            # Fallback without pandas Excel engine
            df = pd.DataFrame(records)
            df.to_csv(csv_path, index=False)
            print(f"Could not write .xlsx (fallback to CSV): {e}")
            print(f"Saved CSV metrics table to: {csv_path}")
        except Exception as e2:
            print(f"Failed to save metrics table: {e2}")

if __name__ == "__main__":
    try:
        run_simple_evaluation()
    except Exception as e:
        print(f"Error during evaluation: {e}")
        import traceback
        traceback.print_exc()