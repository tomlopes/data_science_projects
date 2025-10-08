# Challenge 4: Semantic Kernel + Azure AI Agent Service Agents: The Best of Both Worlds

**Expected Duration:** 60 minutes

## Introduction
By this point we have created **one agent** and have seen how to evaluate and observe that specific agent. As you know, our use case is a bit more complex and, therefore, we will now create additional specialized agents to handle different aspects of insurance claim processing. In this challenge, we'll focus on building individual agents with enhanced capabilities using Semantic Kernel integration.

## What are we building?
In this challenge, we will create specialized AI agents that can work independently on different aspects of insurance processing:

- **Policy Checker Agent**: Validates insurance policy coverage and checks claim eligibility [already created!]
- **Claim Reviewer Agent**: Reviews and analyzes insurance claim submissions and documentation  
- **Risk Analyser Agent**: Evaluates risk factors and detects potential fraud patterns

Each agent will be built using Azure AI Agent Service combined with Semantic Kernel's powerful plugin system, giving them enhanced capabilities and better integration options.

## Why Semantic Kernel?
Semantic Kernel serves as an excellent foundation for Azure AI Agent Service agents because it enables modular, scalable, and flexible development of specialized AI agents. With its robust plugin framework, Semantic Kernel efficiently manages complex agent capabilities by allowing seamless integration of diverse AI models and enterprise functions, while providing advanced capabilities out-of-the-box, such as prompt chaining, context management, and seamless API integration. The combination of Semantic Kernel's open-source flexibility and Azure's enterprise-grade AI services empowers developers to construct sophisticated, reliable, and easily maintained AI solutions.

## Exercise Guide - Create your Agents!

### Part 1 - Create your Claim Reviewer Agent

Time to build our second agent! Please jump over to `claim_reviewer.ipynb` file for a demonstration on how to create an Azure AI Agent using a Custom Plugin from Semantic Kernel. Please make sure to carefully check all the cells, as they have interesting integrations.

### Part 2 - Create your Risk Analyser Agent

Time to build our third agent! Please jump over to `risk_analyser.ipynb` file for a demonstration on how to create an Azure AI Agent using a Custom Plugin from Semantic Kernel.

Great! If you are finished, and you are ready to take on an extra challenge, I have good news for you: there's so much more to expand! 

### Part 3 - Use your Memory! (Optional)
Part of this code-first experience is the fact that we are indeed writing code. Within your environment you have access to **Github Copilot for free**! 

GitHub Copilot accelerates AI agent development by providing intelligent code suggestions and completions, making it easier to implement complex agent capabilities and semantic kernel integrations.

For the sake of time, you will want it as your helper. Your Optional challenge to continue this journey forward is to use your Cosmos DB platform as your memory. 

You can find an easy Implementation sample on our official [documentation](https://learn.microsoft.com/en-us/azure/cosmos-db/ai-agents#implementation-sample).


## Solution Folder

The `solution` folder contains the complete implementation of our specialized insurance processing agents, showcasing the practical application of Semantic Kernel integration with Azure AI Agent Service.

### What's in the Solution?

The solution folder includes three specialized agent implementations:

| Agent Notebook | Purpose | Specialization |
|----------------|---------|----------------|
| `policy_checker.ipynb` | **Policy Analysis Agent** | Validates insurance policy coverage, checks claim eligibility, and interprets policy terms and conditions |
| `claim_reviewer.ipynb` | **Claim Assessment Agent** | Reviews and analyzes insurance claim submissions, damage assessments, and claim documentation |
| `risk_analyser.ipynb` | **Risk Analysis Agent** | Evaluates risk factors, detects potential fraud patterns, and assesses claim authenticity |

### Implementation Focus

Each notebook demonstrates:

- **Azure AI Agent Creation**: How to instantiate and configure specialized agents using Azure AI Agent Service
- **Semantic Kernel Integration**: Custom plugin development for enhanced agent capabilities
- **Knowledge Base Integration**: Connection to Azure AI Search for accessing vectorized insurance documents
- **Advanced Functionality**: Implementation of specialized processing logic for each agent's domain
- **Context Management**: Proper handling of information and state within individual agents

This solution demonstrates the power of combining Azure AI Agent Service's enterprise-grade capabilities with Semantic Kernel's flexible plugin framework, creating robust, scalable, and maintainable specialized agents that will serve as the foundation for your multi-agent system in the next challenge.


## What's Next? Agent Orchestration!

Now that you have built individual specialized agents, you're ready for the next level: **Agent Orchestration**! In Challenge 5, you'll learn how to coordinate these multiple agents to work together on complex tasks that require collaboration between different specializations. 

You'll discover orchestration patterns like Sequential, Concurrent, and Group Chat orchestration, and implement a sophisticated multi-agent system where your Policy Checker, Claim Reviewer, and Risk Analyser agents collaborate seamlessly to process insurance claims end-to-end. This is where the real power of multi-agent systems comes alive!

---
