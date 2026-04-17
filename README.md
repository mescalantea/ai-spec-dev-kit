# Spec-Driven Toolkit

A practical toolkit to adopt **Spec-Driven Development (SDD)** in modern software projects using AI-assisted workflows.

It provides scripts, templates, and conventions to help teams move from idea → specification → implementation in a structured, repeatable way.

---

## 🚀 What is Spec-Driven Development?

Spec-Driven Development is an approach where **specifications are the primary source of truth**, guiding implementation rather than being an afterthought. This becomes especially powerful when combined with AI tools that can interpret and act on well-structured specifications.

---

## 📦 What’s included

- **Spec template**  
  Predefined Markdown template for a specification file.

- **Automation scripts**  
  Setup the tool in your project.

- **AI tooling**  
  Commands and skills to allow AI to work with specs effectively.

---

## 🧠 Goals

- Make specs the **single source of truth**. By default, the spec is written into a markdown file that lives in the codebase, but it can live in other places as well (Jira or YouTrack tickets). The key is that the spec is the source of truth for the implementation, and that it is easily accessible to all stakeholders. Additionally, because the whole process is split into multiple steps, it allows teams to review and refine the spec before implementation starts, which can help to catch issues early and ensure that everyone is on the same page.
- Improve **consistency** across teams and projects by standardizing how specifications are written and used.
- Enable **AI-assisted development workflows** that don't rely on Vibe Coding and follow a well-defined process, improving efficiency, software quality and team collaboration.
- Add some extra **cool** optimizations to help saving tokens through the process, interact with GitHub and Jira, and more.

---

## 🏗️ Project Structure

```
.
├── ai/              # AI-related tooling and commands
│   ├── claude/
│       ├── commands/
│       ├── skills/
├── templates/          # Reusable spec template
├── scripts/            # Automation and tooling
└── README.md
```

---

## ⚡ Getting Started

1. Clone the repository:

```bash
git clone https://github.com/mescalantea/ai-spec-dev-kit.git
cd ai-spec-dev-kit
```

> [!NOTE]
> 🚧 Work in progress
