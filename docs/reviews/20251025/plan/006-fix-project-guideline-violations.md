# Task: Fix Phoenix 1.8 Project Guideline Violations

## Category
Code Quality, Compliance

## Priority
**HIGH** - Non-compliance with Phoenix 1.8 patterns and project guidelines

## Description
The application violates multiple Phoenix 1.8 guidelines and best practices defined in AGENTS.md, including inline scripts, improper component usage, missing layout wrappers, and incorrect form patterns. These violations make the code inconsistent and harder to maintain.

## Current State

### Violation 1: Inline Script in Layout
```html
<!-- lib/live_poll_web/components/layouts/root.html.heex -->
<script>
  // Theme toggle script should be in assets/js/
  function toggleTheme() {
    // Inline JavaScript violates guidelines
  }
</script>
```

### Violation 2: Flash Group Misuse
```elixir
# LiveView template calling flash_group (FORBIDDEN)
~H"""
<Layouts.flash_group flash={@flash} />
"""
# flash_group should ONLY be called inside layouts.ex module
```

### Violation 3: Missing Layout Wrapper
```elixir
# LiveView template not wrapped with <Layouts.app>
def render(assigns) do
  ~H"""
  <div class="container">
    <!-- Content not wrapped in Layouts.app -->
  </div>
  """
end
```

### Violation 4: Incorrect Form Patterns
```elixir
# Current: Raw HTML forms
<form phx-submit="add_language">
  <input type="text" name="name" />
</form>

# Should use: Phoenix.Component form helpers
<.form for={@form} id="language-form" phx-submit="add_language">
  <.input field={@form[:name]} type="text" />
  <.button type="submit">Add</.button>
</.form>
```

### Violation 5: DaisyUI Usage
```css
/* Using DaisyUI contrary to guidelines */
@plugin "../vendor/daisyui" {
  themes: false;
}
```

## Proposed Solution

### Fix 1: Move Theme Toggle to app.js
```javascript
// assets/js/app.js
// Add theme toggle functionality
const ThemeToggle = {
  mounted() {
    this.theme = localStorage.getItem('theme') || 'light';
    this.applyTheme();
    
    this.el.addEventListener('click', () => {
      this.theme = this.theme === 'light' ? 'dark' : 'light';
      this.applyTheme();
      localStorage.setItem('theme', this.theme);
    });
  },
  
  applyTheme() {
    document.documentElement.classList.toggle('dark', this.theme === 'dark');
    this.el.textContent = this.theme === 'light' ? '🌙' : '☀️';
  }
};

// Register hook
let Hooks = {
  ThemeToggle,
  // ... other hooks
};
```

Remove inline script from root.html.heex:
```heex
<!-- lib/live_poll_web/components/layouts/root.html.heex -->
<!-- Remove all <script> tags -->
<button id="theme-toggle" phx-hook="ThemeToggle">🌙</button>
```

### Fix 2: Remove Flash Group from LiveView
```elixir
# lib/live_poll_web/components/layouts.ex
defmodule LivePollWeb.Layouts do
  use LivePollWeb, :html
  
  embed_templates "layouts/*"
  
  # flash_group stays here - ONLY place it should be
  def flash_group(assigns) do
    ~H"""
    <.flash :if={@flash} kind={:info} flash={@flash} />
    <.flash :if={@flash} kind={:error} flash={@flash} />
    """
  end
end

# lib/live_poll_web/components/layouts/app.html.heex
# Ensure flash_group is called here, not in LiveViews
<main>
  <.flash_group flash={@flash} />
  <%= @inner_content %>
</main>
```

### Fix 3: Wrap LiveView with Layouts.app
```elixir
# lib/live_poll_web/live/poll_live.ex
def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash} current_scope={@current_scope}>
    <div class="container mx-auto px-4">
      <header class="py-8">
        <h1 class="text-4xl font-bold text-center">
          Programming Language Poll
        </h1>
      </header>
      
      <!-- Rest of poll content -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
        <!-- Poll options -->
        <!-- Charts -->
      </div>
    </div>
  </Layouts.app>
  """
end

# Ensure current_scope is assigned in mount
def mount(_params, _session, socket) do
  {:ok, 
   socket
   |> assign(:current_scope, nil)  # or appropriate scope
   |> load_data()}
end
```

### Fix 4: Use Proper Form Components
```elixir
# lib/live_poll_web/live/poll_live.ex
def render(assigns) do
  ~H"""
  <!-- Language addition form -->
  <.form for={@form} id="language-form" phx-submit="add_language" class="flex gap-2">
    <.input 
      field={@form[:name]} 
      type="text" 
      placeholder="Enter language name"
      class="flex-1"
    />
    <.button type="submit" phx-disable-with="Adding...">
      Add Language
    </.button>
  </.form>
  """
end

def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:form, to_form(%{"name" => ""}))}
end

def handle_event("add_language", %{"name" => name}, socket) do
  changeset = language_changeset(%{"name" => name})
  
  if changeset.valid? do
    case Polls.add_language(name) do
      {:ok, option} ->
        {:noreply,
         socket
         |> assign(:form, to_form(%{"name" => ""}))
         |> put_flash(:info, "Added #{option.text}")}
      
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  else
    {:noreply, assign(socket, :form, to_form(changeset))}
  end
end
```

### Fix 5: Remove DaisyUI Completely
```css
/* assets/css/app.css */
/* Remove DaisyUI import */
/* @plugin "../vendor/daisyui" - DELETE THIS */

/* Use custom Tailwind components instead */
@import "tailwindcss" source(none);
@source "../css";
@source "../js"; 
@source "../../lib/live_poll_web";

/* Custom button styles instead of DaisyUI */
.btn-primary {
  @apply px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 
         focus:outline-none focus:ring-2 focus:ring-blue-500 
         transition-colors duration-200;
}

.btn-secondary {
  @apply px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700
         focus:outline-none focus:ring-2 focus:ring-gray-500
         transition-colors duration-200;
}
```

Remove DaisyUI files:
```bash
rm assets/vendor/daisyui.js
rm assets/vendor/daisyui-theme.js
```

### Fix 6: Use Icon Component Instead of Heroicons Module
```elixir
# Current (WRONG):
<Heroicons.check_circle class="w-5 h-5" />

# Correct:
<.icon name="hero-check-circle" class="w-5 h-5" />
```

## Requirements
1. ✅ Remove all inline scripts from templates
2. ✅ Move flash_group to layouts module only
3. ✅ Wrap LiveView content with <Layouts.app>
4. ✅ Use proper Phoenix.Component form helpers
5. ✅ Remove DaisyUI completely
6. ✅ Use <.icon> component for icons
7. ✅ Follow Tailwind v4 import syntax

## Definition of Done
1. **Code Compliance**
   - [ ] No inline <script> tags in templates
   - [ ] flash_group only in layouts.ex
   - [ ] LiveView wrapped with Layouts.app
   - [ ] Forms use <.form> and <.input> components
   - [ ] DaisyUI removed from project

2. **Functionality Preserved**
   - [ ] Theme toggle still works
   - [ ] Forms still functional
   - [ ] Styling maintained or improved
   - [ ] Flash messages display correctly

3. **Tests**
   - [ ] All existing tests pass
   - [ ] Theme toggle works via Hook
   - [ ] Forms submit correctly

4. **Quality Checks**
   - [ ] `mix format` passes
   - [ ] No console errors
   - [ ] Guidelines compliance verified

## Branch Name
`fix/phoenix-guideline-compliance`

## Dependencies
None - Can be done independently

## Estimated Complexity
**M (Medium)** - 3-4 hours

## Testing Instructions
1. Move theme toggle to JavaScript hook
2. Test theme switching works and persists
3. Fix flash group location
4. Wrap LiveView with Layouts.app
5. Convert forms to use Phoenix components
6. Remove DaisyUI and test styling
7. Verify all functionality preserved
8. Run test suite

## Checklist
- [ ] root.html.heex has no <script> tags
- [ ] Theme toggle uses phx-hook
- [ ] flash_group only in layouts.ex
- [ ] LiveView template starts with <Layouts.app>
- [ ] Forms use <.form> component
- [ ] Forms use <.input> component  
- [ ] DaisyUI removed from package.json
- [ ] DaisyUI imports removed from CSS
- [ ] Custom Tailwind styles replace DaisyUI classes
- [ ] Icons use <.icon> component

## Notes
- These violations make the code harder to maintain
- Following guidelines ensures consistency across Phoenix apps
- Removing DaisyUI saves ~300KB bundle size
- Proper component usage enables better testing
