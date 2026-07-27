#!/bin/bash
# check_integration.sh - Verify fork integration status

echo "🔍 Enchanted Fork Integration Checker"
echo "===================================="
echo ""

errors=0
warnings=0

# Check if Swift files exist
echo "📁 Checking Swift files..."
swift_files=(
    "ExportModels.swift"
    "ExportService.swift"
    "ExportView.swift"
    "ExportButton.swift"
    "AgentModels.swift"
    "AgentService.swift"
    "AgentStore.swift"
    "ModelExtensions.swift"
    "LanguageModelStore+Agents.swift"
    "AgentBadge.swift"
    "AgentDebugView.swift"
)

for file in "${swift_files[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file"
    else
        echo "  ❌ $file - MISSING"
        ((errors++))
    fi
done

echo ""
echo "📝 Checking Python tools..."
python_files=(
    "import_enchanted.py"
    "test_export.py"
)

for file in "${python_files[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file"
        # Check if executable
        if [ -x "$file" ]; then
            echo "     (executable)"
        else
            echo "     ⚠️  not executable (run: chmod +x $file)"
            ((warnings++))
        fi
    else
        echo "  ❌ $file - MISSING"
        ((errors++))
    fi
done

echo ""
echo "🔧 Checking integration points..."

# Check if ConversationStore has agent support
if grep -q "sendAgentPrompt" ConversationStore.swift 2>/dev/null; then
    echo "  ✅ ConversationStore.swift has agent support"
else
    echo "  ❌ ConversationStore.swift missing agent support"
    ((errors++))
fi

# Check if ApplicationEntry loads agents
if [ -f "ApplicationEntry.swift" ]; then
    if grep -q "loadModelsAndAgents" ApplicationEntry.swift; then
        echo "  ✅ ApplicationEntry.swift calls loadModelsAndAgents()"
    else
        echo "  ⚠️  ApplicationEntry.swift still calls loadModels()"
        echo "     Update to: languageModelStore.loadModelsAndAgents()"
        ((warnings++))
    fi
else
    echo "  ❓ ApplicationEntry.swift not found"
fi

# Check for export button integration
has_export_button=false
if grep -q "ExportButton\|ExportToolbarButton" ChatView_iOS.swift 2>/dev/null; then
    echo "  ✅ Export button found in ChatView_iOS.swift"
    has_export_button=true
elif grep -q "ExportButton\|ExportToolbarButton" ChatView_macOS.swift 2>/dev/null; then
    echo "  ✅ Export button found in ChatView_macOS.swift"
    has_export_button=true
fi

if ! $has_export_button; then
    echo "  ⚠️  Export button not integrated into UI"
    echo "     Add ExportButton or ExportToolbarButton to a view"
    ((warnings++))
fi

echo ""
echo "📚 Checking documentation..."
docs=(
    "ENCHANTED_FORK_README.md"
    "IMPLEMENTATION_SUMMARY.md"
    "INTEGRATION_GUIDE.md"
    "README_IMPLEMENTATION.md"
)

for doc in "${docs[@]}"; do
    if [ -f "$doc" ]; then
        echo "  ✅ $doc"
    else
        echo "  ⚠️  $doc - missing but optional"
    fi
done

echo ""
echo "===================================="
echo "Summary:"
echo "  Errors: $errors"
echo "  Warnings: $warnings"
echo ""

if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo "✅ All checks passed!"
    echo ""
    echo "Next steps:"
    echo "  1. Build the app in Xcode"
    echo "  2. Configure Osaurus endpoint + bearer token in Settings"
    echo "  3. Test export button"
    echo "  4. Test agent discovery"
    echo ""
    echo "See INTEGRATION_GUIDE.md for detailed instructions."
    exit 0
elif [ $errors -eq 0 ]; then
    echo "⚠️  Integration incomplete (warnings only)"
    echo ""
    echo "Review warnings above and see INTEGRATION_GUIDE.md"
    exit 0
else
    echo "❌ Integration incomplete (errors found)"
    echo ""
    echo "Fix errors above before building."
    exit 1
fi
