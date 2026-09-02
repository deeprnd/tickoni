"""Dependency resolution and tool collection."""


class DependencyResolver:
    """Resolve category dependencies recursively with cycle detection."""

    def __init__(self, dependencies):
        self.dependencies = dependencies
        self.resolved = []
        self.visiting = set()

    def resolve(self, requested):
        """Resolve category dependencies. Detects cycles."""
        self.resolved = []
        self.visiting = set()
        for cat in requested:
            self._visit(cat)
        return self.resolved

    def _visit(self, cat):
        if cat in self.resolved:
            return
        if cat in self.visiting:
            print(f"ERROR: circular dependency detected: {cat}", file=__import__('sys').stderr)
            __import__('sys').exit(1)
        self.visiting.add(cat)
        for dep in self.dependencies.get(cat, []):
            self._visit(dep)
        self.resolved.append(cat)
        self.visiting.discard(cat)

    def collect(self, resolved_categories, categories_config, tools_config):
        """Collect all tools from resolved categories, preserving dependency order."""
        tools = []
        seen = set()
        for cat in resolved_categories:
            cat_info = categories_config.get(cat, {})
            for tool_name in cat_info.get('tools', []):
                if tool_name not in seen and tool_name in tools_config:
                    tool = tools_config[tool_name].copy()
                    tool['name'] = tool_name
                    tool['category'] = cat
                    # Propagate top-level version_ref into parameters so
                    # install strategies can read it via params.get('version_ref')
                    if 'version_ref' in tool:
                        tool.setdefault('parameters', {})
                        tool['parameters']['version_ref'] = tool['version_ref']
                    tools.append(tool)
                    seen.add(tool_name)
        return tools
