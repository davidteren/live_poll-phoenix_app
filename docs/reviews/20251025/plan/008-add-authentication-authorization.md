# Task: Add Authentication and Authorization for Admin Functions

## Category
Security

## Priority
**CRITICAL** - Anyone can reset votes or trigger expensive operations

## Description
The application has no authentication or authorization, allowing any user to perform administrative actions like resetting all votes, seeding data, or potentially destructive operations. Basic authentication must be added to protect sensitive functions.

## Current State
```elixir
# Anyone can do this!
def handle_event("reset_votes", _params, socket) do
  Repo.delete_all(VoteEvent)  # No auth check!
  # Reset all votes to zero
end

def handle_event("seed_data", _params, socket) do
  # Expensive operation anyone can trigger
  seed_votes(10_000)
end
```

## Proposed Solution

### Step 1: Add Basic Authentication Module
```elixir
# lib/live_poll_web/auth.ex
defmodule LivePollWeb.Auth do
  @moduledoc """
  Simple authentication for admin functions
  """
  
  import Plug.Conn
  import Phoenix.Controller
  
  @admin_username System.get_env("ADMIN_USERNAME") || "admin"
  @admin_password_hash System.get_env("ADMIN_PASSWORD_HASH") || hash_password("admin123")
  
  @doc """
  Plug to require authentication for admin routes
  """
  def require_admin(conn, _opts) do
    if admin_authenticated?(conn) do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> put_view(LivePollWeb.ErrorHTML)
      |> render(:"401")
      |> halt()
    end
  end
  
  @doc """
  Check if current session is admin authenticated
  """
  def admin_authenticated?(conn) do
    get_session(conn, :admin_authenticated) == true
  end
  
  @doc """
  Authenticate admin credentials
  """
  def authenticate_admin(username, password) do
    if username == @admin_username && verify_password(password, @admin_password_hash) do
      {:ok, :admin}
    else
      {:error, :invalid_credentials}
    end
  end
  
  @doc """
  Mark session as admin authenticated
  """
  def login_admin(conn) do
    conn
    |> put_session(:admin_authenticated, true)
    |> put_session(:admin_logged_in_at, DateTime.utc_now())
    |> configure_session(renew: true)
  end
  
  @doc """
  Remove admin authentication from session
  """
  def logout_admin(conn) do
    conn
    |> clear_session()
    |> configure_session(drop: true)
  end
  
  defp hash_password(password) do
    # Use Argon2 for production
    :crypto.hash(:sha256, password) |> Base.encode16()
  end
  
  defp verify_password(password, hash) do
    hash_password(password) == hash
  end
end
```

### Step 2: Create Admin Login LiveView
```elixir
# lib/live_poll_web/live/admin_login_live.ex
defmodule LivePollWeb.AdminLoginLive do
  use LivePollWeb, :live_view
  alias LivePollWeb.Auth
  
  def mount(_params, session, socket) do
    # Redirect if already authenticated
    if Map.get(session, "admin_authenticated") == true do
      {:ok, push_navigate(socket, to: "/")}
    else
      {:ok,
       socket
       |> assign(:form, to_form(%{"username" => "", "password" => ""}))
       |> assign(:error, nil)}
    end
  end
  
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50 dark:bg-gray-900">
      <div class="max-w-md w-full space-y-8">
        <div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900 dark:text-white">
            Admin Login
          </h2>
          <p class="mt-2 text-center text-sm text-gray-600 dark:text-gray-400">
            Sign in to access administrative functions
          </p>
        </div>
        
        <.form for={@form} id="login-form" phx-submit="login" class="mt-8 space-y-6">
          <div class="rounded-md shadow-sm -space-y-px">
            <div>
              <.input
                field={@form[:username]}
                type="text"
                label="Username"
                required
                autocomplete="username"
                class="rounded-t-md"
              />
            </div>
            <div>
              <.input
                field={@form[:password]}
                type="password"
                label="Password"
                required
                autocomplete="current-password"
                class="rounded-b-md"
              />
            </div>
          </div>
          
          <%= if @error do %>
            <div class="text-red-600 text-sm text-center">
              <%= @error %>
            </div>
          <% end %>
          
          <div>
            <.button type="submit" class="w-full" phx-disable-with="Signing in...">
              Sign in
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
  
  def handle_event("login", %{"username" => username, "password" => password}, socket) do
    case Auth.authenticate_admin(username, password) do
      {:ok, :admin} ->
        # Can't modify conn from LiveView, need to redirect through controller
        {:noreply,
         socket
         |> put_flash(:info, "Successfully logged in as admin")
         |> push_event("admin_login", %{username: username, password: password})}
      
      {:error, :invalid_credentials} ->
        {:noreply,
         socket
         |> assign(:error, "Invalid username or password")
         |> assign(:form, to_form(%{"username" => username, "password" => ""}))}
    end
  end
end
```

### Step 3: Add Admin Controller for Session Management
```elixir
# lib/live_poll_web/controllers/admin_controller.ex
defmodule LivePollWeb.AdminController do
  use LivePollWeb, :controller
  alias LivePollWeb.Auth
  
  def login(conn, %{"username" => username, "password" => password}) do
    case Auth.authenticate_admin(username, password) do
      {:ok, :admin} ->
        conn
        |> Auth.login_admin()
        |> put_flash(:info, "Welcome, admin!")
        |> redirect(to: ~p"/")
      
      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid credentials")
        |> redirect(to: ~p"/admin/login")
    end
  end
  
  def logout(conn, _params) do
    conn
    |> Auth.logout_admin()
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: ~p"/")
  end
end
```

### Step 4: Update Router with Auth Routes
```elixir
# lib/live_poll_web/router.ex
defmodule LivePollWeb.Router do
  use LivePollWeb, :router
  import LivePollWeb.Auth, only: [require_admin: 2]
  
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {LivePollWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end
  
  pipeline :admin do
    plug :require_admin
  end
  
  # Public routes
  scope "/", LivePollWeb do
    pipe_through :browser
    
    live "/", PollLive, :index
    live "/admin/login", AdminLoginLive, :login
    post "/admin/login", AdminController, :login
  end
  
  # Admin routes
  scope "/admin", LivePollWeb do
    pipe_through [:browser, :admin]
    
    get "/logout", AdminController, :logout
  end
end
```

### Step 5: Add Role-Based Access in LiveView
```elixir
# lib/live_poll_web/live/poll_live.ex
defmodule LivePollWeb.PollLive do
  use LivePollWeb, :live_view
  
  def mount(_params, session, socket) do
    # Check admin status from session
    is_admin = Map.get(session, "admin_authenticated") == true
    
    if connected?(socket) do
      Phoenix.PubSub.subscribe(LivePoll.PubSub, "poll:updates")
    end
    
    {:ok,
     socket
     |> assign(:is_admin, is_admin)
     |> load_data()}
  end
  
  def render(assigns) do
    ~H"""
    <div class="container mx-auto">
      <!-- Regular voting UI available to all -->
      <div class="voting-section">
        <!-- ... voting buttons ... -->
      </div>
      
      <!-- Admin controls only visible to admins -->
      <%= if @is_admin do %>
        <div class="admin-controls mt-8 p-4 border-2 border-red-500 rounded">
          <h3 class="text-lg font-bold text-red-600 mb-4">Admin Controls</h3>
          
          <div class="flex gap-4">
            <.button phx-click="reset_votes" 
                     data-confirm="Are you sure? This will reset ALL votes!"
                     class="bg-red-600 hover:bg-red-700">
              Reset All Votes
            </.button>
            
            <.button phx-click="show_seed_modal" class="bg-blue-600 hover:bg-blue-700">
              Seed Test Data
            </.button>
            
            <.link href="/admin/logout" method="get" 
                   class="bg-gray-600 hover:bg-gray-700 text-white px-4 py-2 rounded">
              Logout Admin
            </.link>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
  
  # Protect admin events
  def handle_event("reset_votes", _params, socket) do
    if socket.assigns.is_admin do
      case LivePoll.Polls.reset_all_votes() do
        {:ok, _} ->
          {:noreply,
           socket
           |> load_data()
           |> put_flash(:info, "All votes have been reset")}
        
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to reset votes")}
      end
    else
      {:noreply, put_flash(socket, :error, "Unauthorized action")}
    end
  end
  
  def handle_event("seed_data", params, socket) do
    if socket.assigns.is_admin do
      # Process seeding
      LivePoll.Polls.seed_votes(params["count"])
      {:noreply, put_flash(socket, :info, "Seeding data...")}
    else
      {:noreply, put_flash(socket, :error, "Unauthorized action")}
    end
  end
  
  # Regular voting remains unrestricted
  def handle_event("vote", %{"id" => id}, socket) do
    # Anyone can vote
    case LivePoll.Polls.cast_vote(id) do
      {:ok, option, _} ->
        {:noreply, update_option_in_socket(socket, option)}
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to record vote")}
    end
  end
end
```

### Step 6: Add Environment Configuration
```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :live_poll, LivePollWeb.Auth,
    admin_username: System.fetch_env!("ADMIN_USERNAME"),
    admin_password_hash: System.fetch_env!("ADMIN_PASSWORD_HASH")
end

# .env.example
ADMIN_USERNAME=admin
ADMIN_PASSWORD_HASH=<generate with mix task>
```

### Step 7: Create Mix Task for Password Hashing
```elixir
# lib/mix/tasks/admin.password.ex
defmodule Mix.Tasks.Admin.Password do
  use Mix.Task
  
  @shortdoc "Hash an admin password for configuration"
  
  def run([password]) do
    Mix.Task.run("app.start")
    
    hash = :crypto.hash(:sha256, password) |> Base.encode16()
    
    IO.puts("Password hash: #{hash}")
    IO.puts("Add this to your environment variables:")
    IO.puts("ADMIN_PASSWORD_HASH=#{hash}")
  end
  
  def run(_) do
    IO.puts("Usage: mix admin.password <password>")
  end
end
```

## Requirements
1. ✅ Implement basic authentication system
2. ✅ Protect admin functions (reset, seed)
3. ✅ Create admin login page
4. ✅ Add session management
5. ✅ Hide admin controls from non-admin users
6. ✅ Environment-based credentials
7. ✅ Secure password storage (hashed)

## Definition of Done
1. **Authentication System**
   - [ ] Auth module with login/logout functions
   - [ ] Admin login page functional
   - [ ] Session management working
   - [ ] Password hashing implemented

2. **Authorization**
   - [ ] Admin functions protected
   - [ ] UI shows admin controls only to admins
   - [ ] Unauthorized attempts rejected
   - [ ] Clear error messages

3. **Tests**
   ```elixir
   test "non-admin cannot reset votes" do
     {:ok, view, _} = live(conn, "/")
     
     # Should not see admin controls
     refute render(view) =~ "Admin Controls"
     
     # Direct event should be rejected
     assert {:error, _} = view
       |> render_event("reset_votes", %{})
   end
   
   test "admin can access admin functions" do
     conn = conn |> init_test_session(admin_authenticated: true)
     {:ok, view, _} = live(conn, "/")
     
     # Should see admin controls
     assert render(view) =~ "Admin Controls"
   end
   ```

4. **Quality Checks**
   - [ ] Credentials not hardcoded
   - [ ] Passwords properly hashed
   - [ ] Session security configured
   - [ ] CSRF protection maintained

## Branch Name
`feature/add-admin-authentication`

## Dependencies
- Should be implemented after rate limiting for complete security

## Estimated Complexity
**M (Medium)** - 4-6 hours

## Testing Instructions
1. Set admin credentials in environment
2. Access /admin/login
3. Try logging in with wrong credentials (should fail)
4. Log in with correct credentials
5. Verify admin controls visible after login
6. Test reset and seed functions (admin only)
7. Verify regular users can still vote
8. Test logout functionality

## Security Checklist
- [ ] Passwords hashed, not plain text
- [ ] Credentials from environment, not code
- [ ] Session properly secured
- [ ] CSRF token validated
- [ ] Admin actions logged
- [ ] Timeout for admin sessions
- [ ] No credentials in logs

## Notes
- Consider adding role-based access control (RBAC) for future
- May want to add two-factor authentication later
- Should add audit logging for admin actions
- Consider using Guardian or similar for production
- Add session timeout for security
