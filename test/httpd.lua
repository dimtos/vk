local clock = require 'clock'
local pkg = { t0 = clock.time(), counter = 0 }

local server = require('http.server').new( app.config.httpd.host, app.config.httpd.port )

local output = function( req, code, res )
	local codes =
		{
			['200'] = function()
				log.error('Request error '.. tostring(200)) -- здесь тупая конкатенация, пониже будет string.format
				return req:render{ json = res }
			end,

			['400'] = function()
				log.error('Request error '.. tostring(400))
				local resp = req:render{ json = { error = 'Incorrect JSON' } }
				resp.status = 400
				return resp
			end,

			['404'] = function()
				log.error('Request error '.. tostring(404))
				local resp = req:render{ json = { error = 'Key not found' } }
				resp.status = 404
				return resp
			end,

			['409'] = function()
				log.error('Request error '.. tostring(409))
				local resp = req:render{ json = { error = 'Key already exists' } }
				resp.status = 409
				return resp
			end,

			['429'] = function()
				log.error('Request error '.. tostring(429))
				local resp = req:render{ json = { error = 'Request limit exceeded' } }
				resp.status = 429
				return resp
			end,
		}
	return req.request_limit_exceeded == true
		and codes['429']()
		or assert( codes[ tostring(code) ] )()
end



--
-- триггер для логирования запросов в БД
--
box.space.test:on_replace(function(old, new, space, op)
	local msg = op:upper() ..' in `'.. space ..'` with key: '.. (new.key or old.key)
	-- жутко медленная фигня, лучше не юзать в таких местах; но мы ведь дебажим...
	-- а попутно я таким образом показываю, что в курсе о триггерах)) в том числе о before_replace, где можно кортеж исправить
	log.info(msg)
end)



server:hook( 'before_dispatch', function(self, req)
	local msg = string.format( 'Request from peer %s', req.peer.host )
	log.info(msg)

	local now = clock.time()
	local diff = clock.time() - pkg.t0
	if diff < 1 then
		pkg.counter = pkg.counter + 1
	else
		pkg.t0 = now
		pkg.counter = 1
	end

	if pkg.counter > app.config.max_queries_per_second then
		req.request_limit_exceeded = true
	end
end)



server:route( { path = '/kv/*key', method = 'GET' },
	function(req)
		local k = req:stash('key')
		local found = box.space.test:select{k}[1] -- это у нас primary_index
		return
			found
			and output( req, 200, found:tomap{names_only = true} )
			or output( req, 404 )
	end
)

server:route( { path = '/kv/*key', method = 'DELETE' },
	function(req)
		local k = req:stash('key')
		local found = box.space.test:delete{k}
		return
			found
			and output( req, 200, {ok = true} )
			or output( req, 404 )
	end
)

server:route( { path = '/kv/*key', method = 'PUT' },
	function(req)
		local k = req:stash('key')
		local ok, body, resp = pcall( req.json, req )
		if not ok or body.value == nil then
			return output( req, 400 )
		end

		local found = box.space.test:update( {k}, {{ '=', 'value', body.value }} )
		return
			found
			and output( req, 200, found:tomap{names_only = true} )
			or output( req, 404 )
	end
)

server:route( { path = '/kv/*key', method = 'POST' },
	function(req)
		local ok, body, resp = pcall( req.json, req )
		if not ok or body.key == nil or body.value == nil then
			return output( req, 400 )
		end

		local space = box.space.test
		local ok, found = pcall( space.insert, space, { body.key, body.value } )
		return ok -- опять же именно в нашем случае единственным случаем, когда не разместится тапл, является дубль ключа, так как остальные проверки проведены ранее
			and output( req, 200, found:tomap{names_only = true} )
			or output( req, 409 )
	end
)

server:start()

return pkg
