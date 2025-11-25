# 5-Minute Demo Guide: Show the Key Features

**Published:** November 2025  
**Category:** Quick Start, Demo Script  
**Reading Time:** 5 minutes

## Purpose: Rapid Capability Demonstration

You have **5 minutes** to demonstrate this application to a decision-maker (CTO, VP Engineering, Security Lead). This guide provides a **battle-tested demo script** that showcases the most impressive features in the shortest time.

---

## Pre-Demo Checklist (2 minutes setup)

Before the demo, verify:

1. **System is running:**
   - Open the application UI (http://localhost:30999 or your deployment URL)
   - Click "System Health" → "Load System Info"
   - Verify all components show "✅" status

2. **Sample data loaded:**
   - If starting fresh, quickly add 2-3 sample documents (see "Quick Sample Data" section below)
   - Or use existing documents from previous testing

3. **Browser setup:**
   - Clear browser console (F12 → Console tab → Clear)
   - Zoom to 100% for clean screenshot/recording
   - Have window in presentation mode (fullscreen)

---

## Quick Sample Data (Use This if Empty)

If you need sample documents, create these three via "Add Document" section:

**Document 1:**
```
Title: MongoDB Security Best Practices
Body: Implement authentication using SCRAM-SHA-256. Enable encryption at rest with KMIP. Configure network isolation using firewall rules. Audit all administrative actions using auditLog. Regularly update to latest security patches.
Tags: security, mongodb, compliance
```

**Document 2:**
```
Title: Kubernetes Deployment Strategy
Body: Deploy MongoDB using the enterprise operator for automated lifecycle management. Configure persistent volumes with high IOPS storage classes. Set resource limits to prevent node overcommitment. Implement pod disruption budgets for high availability. Use network policies for isolation.
Tags: kubernetes, deployment, infrastructure
```

**Document 3:**
```
Title: Vector Search Performance Tuning
Body: Optimize numCandidates parameter based on dataset size. Use appropriate similarity metric for your embedding model. Consider pre-filtering with $match stage before $vectorSearch. Monitor index build status and search latency. Scale horizontally by adding search nodes.
Tags: vector-search, performance, optimization
```

**Time: 2 minutes to add all three**

---

## The 5-Minute Demo Script

### **Minute 1: Show the Problem (Traditional Search Fails)**

**Say:** *"Let me show you why traditional keyword search isn't enough for modern applications."*

**Action:**
1. Go to "Search Documents" section
2. **Disable** "Semantic Search" toggle (use keyword search)
3. Search: `"improving database speed"`
4. **Show result:** Probably zero or poor results (those exact words may not appear)

**Key Point:** *"Notice how keyword search requires exact word matches. If our documents say 'performance optimization' instead of 'speed', we find nothing."*

---

### **Minute 2: Show the Solution (Vector Search Works)**

**Say:** *"Now watch what happens with semantic vector search."*

**Action:**
1. **Enable** "Semantic Search" toggle
2. Search the same query: `"improving database speed"`
3. **Show result:** Finds Document 1 and Document 3 (relevant despite different terminology)
4. **Click "Show Query Details"** (if available) to show the MongoDB `$vectorSearch` aggregation

**Key Point:** *"Vector search understands meaning, not just keywords. It found 'performance optimization' and 'security patches' because they relate to database speed—even though we used different words."*

---

### **Minute 3: Show AI-Powered Q&A (RAG)**

**Say:** *"Here's where it gets powerful. You can ask questions in plain English."*

**Action:**
1. Scroll to "Chat with Documents (RAG)" section
2. Ask: `"How do I secure my MongoDB database?"`
3. **Wait for response** (~5-10 seconds)
4. **Show the answer** (should mention authentication, encryption, auditing from Document 1)
5. **Show "Sources"** section (cites Document 1)

**Key Point:** *"This isn't ChatGPT making things up. It retrieved our security document, then generated an answer based ONLY on what we've provided. See the sources cited? This is verifiable, not hallucinated."*

**If time permits (+30 seconds):**
- Ask a second question: `"What should I monitor for performance issues?"`
- Show it retrieves Document 3 and answers from that context

---

### **Minute 4: Show Speech-to-Text (Unique Capability)**

**Say:** *"Now the killer feature for airgapped environments: local speech-to-text."*

**Action:**
1. Go to "Audio to Document" section
2. **Option A (if you have audio file ready):**
   - Upload pre-recorded audio (30-second clip saying "MongoDB deployment best practices include using replica sets for high availability...")
   - Show transcription progress
   - Show final transcript and auto-generated document

   **Option B (if no audio file):**
   - **Explain:** *"Normally I'd upload an audio file here. In 8 seconds, Whisper AI would transcribe it—completely offline, no cloud APIs. This is critical for classified or HIPAA-protected audio."*
   - Show the UI elements (drag-drop zone, language selector, etc.)

**Key Point:** *"This is running on-premises. No audio leaves your network. Whisper AI, which powers this, is the same technology OpenAI uses, but we're running it locally. For defense, healthcare, or finance, this means zero compliance risk."*

---

### **Minute 5: Show the Architecture (Why It Matters)**

**Say:** *"Let me show you what's running under the hood."*

**Action:**
1. Click "System Health" section → "Load System Info"
2. **Point out key components:**
   - **MongoDB status:** Version (Enterprise 8.2.1), replica set
   - **Vector Search index:** Status = READY
   - **Ollama LLM:** Model loaded (phi)
   - **Backend AI models:** Whisper (audio), SentenceTransformer (embeddings)

**Say:** *"Everything you just saw is running on-premises:"*
- **MongoDB Enterprise** with native vector search (mongot)
- **Whisper AI** for transcription (no cloud)
- **SentenceTransformer** for embeddings (no cloud)
- **Ollama LLM** for chat (no cloud)

**Key Point:** *"This isn't calling OpenAI or Google. It's 100% airgapped. Once deployed, it works forever without internet. That's why defense contractors, banks, and hospitals can actually use this."*

---

## Alternative Demo: If You Have 10 Minutes

### **Bonus Minute 6-7: Live Audio Recording**

If your device has a microphone and browser permissions:

1. Use **"Record Audio"** button (if implemented)
2. Speak for 10 seconds: *"Vector search enables semantic similarity matching using embeddings generated by neural networks. This allows finding documents based on meaning rather than keywords."*
3. Stop recording → Upload → Show transcription
4. Search for: `"AI document search"` (should find your recording)

**Impact:** *This demonstrates the complete end-to-end flow in real-time.*

### **Bonus Minute 8-9: Custom RAG Prompts**

1. Expand "Custom System Prompt" in Chat section
2. Change to: `"You are a senior database architect. Provide detailed technical explanations with specific MongoDB commands when applicable."`
3. Ask: `"How do I secure MongoDB?"`
4. **Show different response style** (more technical, command-focused)
5. Change prompt to: `"You are a CTO. Provide executive summaries in 2-3 sentences."`
6. Ask same question, get concise answer

**Impact:** *Same technology, different personas. No retraining required.*

### **Bonus Minute 10: Show Ops Manager (If Full Kubernetes)**

1. Open Ops Manager URL (http://localhost:8080 if port-forwarded)
2. Show MongoDB metrics: query performance, replica set status
3. Show deployment automation: "This is how you'd manage 100+ databases"

**Impact:** *Enterprise-grade management, not just a demo.*

---

## Common Questions & Answers (Be Prepared)

**Q: "What if I have 10 million documents?"**
**A:** *"This demo runs on 6-7 CPUs. For 10M docs, you'd scale horizontally—add more mongot search nodes. MongoDB handles petabyte-scale deployments. We can discuss sizing for your specific needs."*

**Q: "Does it work with my language (Spanish, Arabic, Chinese)?"**
**A:** *"The current model is optimized for English, but we can swap to a multilingual embedding model in 10 minutes. Whisper already supports 99 languages out of the box for transcription."*

**Q: "How much does MongoDB Enterprise cost?"**
**A:** *"Licensing varies by scale, but for airgapped deployments, you own the hardware so there's no per-API-call charges like cloud services. Typical break-even is 8-12 months compared to AWS/OpenAI costs."*

**Q: "Can I see the code?"**
**A:** *"Absolutely. This is fully open-source (Apache 2.0). The entire repository—deployment scripts, backend API, frontend UI—is available. You can audit every line before deploying."*

**Q: "What about GPU acceleration?"**
**A:** *"This demo runs CPU-only to show minimal hardware requirements. Add a GPU and RAG responses go from 10 seconds to <1 second. Vector search and embeddings also benefit from GPU but aren't required."*

---

## Post-Demo: What to Send

After the demo, send stakeholders:

1. **Recording/screenshots** from the demo
2. **Link to repository:** https://github.com/[your-repo]
3. **Key docs:**
   - System Requirements
   - Architecture Deep Dive
   - Use Cases (Defense/Finance/Healthcare)
4. **Sizing calculator:** Based on their document volume

---

## Demo Environment Tips

### **For Virtual Demos (Zoom, Teams)**

- **Share application window only** (not entire screen—avoids distractions)
- **Use "Zoom to Fit" in browser** (makes UI elements larger)
- **Clear browser notifications** (disable before demo)
- **Have backup:** Screenshot/video of demo in case of technical issues

### **For In-Person Demos**

- **Bring printed architecture diagram** (visual aid for technical discussion)
- **Have laptop pre-configured** (don't make them wait for startup)
- **Bring HDMI adapter** (always assume incompatible ports)
- **Offline copy of docs** (PDFs of key articles in case internet fails)

### **For Secure Facilities (Airgapped Demo)**

- **Transfer via approved method:** USB drive (scanned), secure file transfer
- **Pre-load on their network** (test deployment day before)
- **Bring printed docs** (no internet to reference online guides)
- **Know firewall rules:** Which ports need to be opened for internal access

---

## Demo Success Metrics

You nailed it if they ask:

1. ✅ **"Can we try this with our actual data?"** (POC request)
2. ✅ **"How long to deploy in production?"** (Implementation timeline)
3. ✅ **"What's the license cost?"** (Procurement question)
4. ✅ **"Can your team help with deployment?"** (Services engagement)

You need more explanation if they say:

1. ❌ **"This seems like ChatGPT, we can just use that."** (Didn't understand airgapped value)
2. ❌ **"Vector search is too complicated for our team."** (Didn't show ease of use)
3. ❌ **"We'll just stick with keyword search."** (Didn't demonstrate semantic advantage)

---

## Final Checklist

**Before the demo:**
- [ ] Application is running and accessible
- [ ] Sample documents are loaded (at least 3)
- [ ] System Health shows all green
- [ ] Audio file prepared (if showing transcription)
- [ ] Browser is in presentation mode

**During the demo:**
- [ ] Start with problem (keyword search fails)
- [ ] Show solution (vector search works)
- [ ] Demonstrate AI (RAG chat)
- [ ] Highlight airgapped (no external APIs)
- [ ] Show architecture (System Health)

**After the demo:**
- [ ] Answer questions (have FAQ ready)
- [ ] Send follow-up materials (docs, links)
- [ ] Schedule next step (POC, sizing call)

---

**Remember:** The goal isn't to show every feature—it's to prove **this solves their problem** (airgapped AI/search) in a way they couldn't do before. Focus on **business value**, not technical wizardry.

**Good luck with your demo! 🚀**

