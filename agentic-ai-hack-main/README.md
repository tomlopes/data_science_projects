# Unlocking Multi-Agent Capabilities with Azure AI Services

Welcome to the Multi-Agent Insurance Claims Processing Hackathon! Today, you'll explore intelligent agent systems powered by Azure AI to streamline complex insurance workflows. Get ready for a hands-on, high-impact day of learning and innovation!

## Introduction
Get ready to transform insurance with AI! In this hackathon, you'll build intelligent agents that process claims, analyze documents, and make smart decisions—just like real insurance pros. From reading handwritten forms to detecting fraud, your agents will collaborate to handle complex workflows in minutes, not weeks. By the end, you'll have created a powerful multi-agent system that redefines insurance claim processing.

## Learning Objectives

By participating in this hackathon, you will learn how to:
- **Build Intelligent Document Systems** using Azure Document Intelligence and GPT-4.1-mini to extract and analyze data from complex insurance documents.
- **Create and Test AI Agents** with Azure AI Agent Service for automated claim processing.
- **Monitor and Evaluate Agents** using Azure AI Foundry for performance, safety, and reliability.
- **Develop Specialized Agents** (e.g., Policy Checker, Claim Reviewer, Risk Analyzer) with Semantic Kernel.
- **Orchestrate Multi-Agent Systems** using Azure Container Apps and advanced coordination patterns for seamless claims handling.

## Architecture
This solution automates insurance claim processing using a multi-agent AI system on Azure. Claims are uploaded along crash documents to Storage Accounts, triggering workflows that clean and structure data with Azure AI Foundry (GPT-4.1-mini). Structured data is stored in Cosmos DB and indexed with Azure AI Search. If you want to know more about how to automatize this, have a look at [last year's hackathon](https://github.com/martaldsantos/doc-process-hack/tree/main/Challenge4). Then, follows the orchestration of specialized AI agents—a Policy Checker, Claim Reviewer, and Risk Analyser—that collaborate to assess claims, detect fraud, and generate a comprehensive summary for human review. Application Insights and Log Analytics monitors the system for performance and reliability, enabling efficient, accurate, and scalable claim handling.

<img width="1828" height="815" alt="image" src="https://github.com/user-attachments/assets/f776cc4b-90da-4898-8a1c-a96282f39bbc" />

## Requirements
To successfully complete this hackathon, you will need the following:

- GitHub account to access the repository and run GitHub Codespaces and Github Copilot.
- Be familiar with Python programming, including handling JSON data and making API calls.​
- Be familiar with Generative AI Solutions and Azure AI Services.
- An active Azure subscription, with Owner or Contributor rights.
- Ability to provision resources in **Sweden Central** or [another supported region](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/concepts/models?tabs=global-standard%2Cstandard-chat-completions#global-standard-model-availability).

## Challenges

- Challenge 00: **[Environment Setup & Azure Resource Deployment](challenge-0/README.md)** : Deploy foundational Azure services and set up your development environment for the hackathon
- Challenge 01: **[Document Processing and Vectorized Search](challenge-1/README.md)**: Build a comprehensive document processing system using multimodal analysis and Azure AI Search for semantic understanding
- Challenge 02: **[Build and Test Your First Agent](challenge-2/README.md)**: Create your first intelligent agent using Azure AI Agent Service to handle insurance claim processing workflows
- Challenge 03: **[Agent Observability and Evaluation](challenge-3/README.md)**: Implement comprehensive observability and evaluation frameworks for your AI agents using Azure AI Foundry's evaluation capabilities
- Challenge 04: **[Semantic Kernel + Azure AI Agent Service Agents](challenge-4/readme.md)**: Create specialized AI agents (Policy Checker, Claim Reviewer, Risk Analyser) using Semantic Kernel integration for enhanced capabilities
- Challenge 05: **[Agent Orchestration](challenge-5/README.md)** Coordinate multiple specialized agents to work together on complex tasks through various orchestration patterns with Azure Container Apps
