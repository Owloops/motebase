/**
 * \file            poll.c
 * \brief           POSIX poll() binding - removes select() FD_SETSIZE limit
 */

/*
 * Based on https://github.com/FreeMasen/luasocket-poll-api-test
 */

#include <lua.h>
#include <lauxlib.h>

#include <poll.h>
#include <errno.h>
#include <string.h>

#define MAX_POLL_FDS 4096

static int
getfd(lua_State *L)
{
    int fd = -1;
    lua_pushstring(L, "getfd");
    lua_gettable(L, -2);
    if (!lua_isnil(L, -1)) {
        lua_pushvalue(L, -2);
        lua_call(L, 1, 1);
        if (lua_isnumber(L, -1)) {
            double numfd = lua_tonumber(L, -1);
            fd = (numfd >= 0.0) ? (int)numfd : -1;
        }
    }
    lua_pop(L, 1);
    return fd;
}

static int
collect_poll_args(lua_State *L, int tab, int fd_to_sock_tab, struct pollfd *fds)
{
    int i = 1, n = 0;

    if (lua_isnil(L, tab)) {
        return 0;
    }
    luaL_checktype(L, tab, LUA_TTABLE);

    for (;;) {
        int fd;
        short events;
        int info;

        lua_pushinteger(L, i);
        lua_gettable(L, tab);
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            break;
        }

        info = lua_gettop(L);

        lua_getfield(L, info, "sock");
        fd = getfd(L);

        if (fd != -1) {
            lua_pushinteger(L, fd);
            lua_pushvalue(L, -2);
            lua_settable(L, fd_to_sock_tab);
        }
        lua_pop(L, 1);

        if (fd != -1 && n < MAX_POLL_FDS) {
            events = POLLERR | POLLHUP;

            lua_getfield(L, info, "read");
            if (lua_toboolean(L, -1)) {
                events |= POLLIN;
            }
            lua_pop(L, 1);

            lua_getfield(L, info, "write");
            if (lua_toboolean(L, -1)) {
                events |= POLLOUT;
            }
            lua_pop(L, 1);

            fds[n].fd = fd;
            fds[n].events = events;
            fds[n].revents = 0;
            n++;
        }

        lua_pop(L, 1);
        i++;
    }
    return n;
}

/**
 * \brief           Poll sockets for I/O readiness
 * \param[in]       L: Lua state (arg1: socket table, arg2: timeout)
 * \return          1 (ready table) or 2 (nil, error)
 */
static int
l_poll(lua_State *L)
{
    struct pollfd fds[MAX_POLL_FDS];
    int fd_to_sock_tab, result_tab;
    int timeout_ms;
    int fd_count, result;
    int ready_count = 0;
    int i;
    double timeout;

    timeout = luaL_optnumber(L, 2, 0);
    timeout_ms = (int)(timeout * 1000);

    lua_settop(L, 2);

    lua_newtable(L);
    fd_to_sock_tab = lua_gettop(L);

    memset(fds, 0, sizeof(fds));
    fd_count = collect_poll_args(L, 1, fd_to_sock_tab, fds);

    result = poll(fds, (nfds_t)fd_count, timeout_ms);

    if (result < 0) {
        const char *error_msg;
        switch (errno) {
        case EFAULT:
            error_msg = "invalid fd provided";
            break;
        case EINTR:
            error_msg = "interrupted";
            break;
        case EINVAL:
            error_msg = "too many sockets";
            break;
        case ENOMEM:
            error_msg = "no memory";
            break;
        default:
            error_msg = "unknown error";
            break;
        }
        lua_pushnil(L);
        lua_pushstring(L, error_msg);
        return 2;
    }

    if (result == 0) {
        lua_pushnil(L);
        lua_pushstring(L, "timeout");
        return 2;
    }

    lua_newtable(L);
    result_tab = lua_gettop(L);

    for (i = 0; i < fd_count; i++) {
        int is_readable = (fds[i].revents & POLLIN) != 0;
        int is_writable = (fds[i].revents & POLLOUT) != 0;

        if (is_readable || is_writable) {
            int entry;

            ready_count++;
            lua_newtable(L);
            entry = lua_gettop(L);

            lua_pushinteger(L, fds[i].fd);
            lua_gettable(L, fd_to_sock_tab);
            lua_setfield(L, entry, "sock");

            lua_pushboolean(L, is_readable);
            lua_setfield(L, entry, "read");

            lua_pushboolean(L, is_writable);
            lua_setfield(L, entry, "write");

            lua_rawseti(L, result_tab, ready_count);
        }
    }

    return 1;
}

static const luaL_Reg poll_funcs[] = {
    {"poll", l_poll},
    {NULL, NULL},
};

int
luaopen_motebase_poll_c(lua_State *L)
{
#if LUA_VERSION_NUM >= 502
    luaL_newlib(L, poll_funcs);
#else
    luaL_register(L, "motebase.poll_c", poll_funcs);
#endif
    lua_pushinteger(L, MAX_POLL_FDS);
    lua_setfield(L, -2, "_MAXFDS");
    return 1;
}
