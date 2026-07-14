try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False

import flask
from flask import Flask, jsonify, render_template
from flask_cors import CORS
import logging
import sys
import threading
import time
import json
import os
from datetime import datetime, timedelta
from pymongo import MongoClient
import pymongo
import certifi

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})

# Global connection status
mt5_connected = False
last_connection_attempt = 0
connection_lock = threading.Lock()

CACHE_FILE = "state_cache.json"

dashboard_state = {
    "account": {},
    "positions": [],
    "history": [],
    "watchlist": [],
    "last_update": None,
    "settings": {
        "target_usd": 2000.0,
        "mock_data_enabled": False,
        "allowed_accounts": [415868928]
    }
}

# MongoDB Settings
MONGO_URI = os.environ.get("MONGO_URI", "mongodb+srv://sainicc01_db_user:AYTi3F5m8rR0uLJT@cluster0.wv9gglp.mongodb.net/?appName=Cluster0")
mongo_client = None
db = None
collection = None
MONGO_CONNECTED = False

def initialize_mongodb():
    global mongo_client, db, collection, MONGO_CONNECTED
    try:
        # Bypass TLS certificate checks to resolve SSL handshake errors on cloud platforms
        mongo_client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000, tlsAllowInvalidCertificates=True)
        # Check connection status
        mongo_client.server_info()
        db = mongo_client["mt5_dashboard"]
        collection = db["dashboard_state"]
        MONGO_CONNECTED = True
        logger.info("Connected to MongoDB Atlas successfully")
        
        # Load initial state from MongoDB
        load_state_from_mongodb()
    except Exception as e:
        MONGO_CONNECTED = False
        logger.error(f"Failed to connect to MongoDB: {str(e)}")

def load_state_from_mongodb():
    global dashboard_state
    if not MONGO_CONNECTED:
        return
    try:
        state = collection.find_one({"_id": "current_state"})
        if state:
            state.pop("_id", None)
            dashboard_state.update(state)
            
            # Ensure settings exist with default fallbacks for legacy DB records
            if "settings" not in dashboard_state or not isinstance(dashboard_state["settings"], dict):
                dashboard_state["settings"] = {}
            defaults = {
                "target_usd": 2000.0,
                "mock_data_enabled": False,
                "allowed_accounts": [415868928]
            }
            for k, v in defaults.items():
                if k not in dashboard_state["settings"]:
                    dashboard_state["settings"][k] = v
                    
            logger.info("Loaded state from MongoDB successfully")
            save_state_cache()
    except Exception as e:
        logger.error(f"Error loading state from MongoDB: {str(e)}")

def save_state_to_mongodb():
    if not MONGO_CONNECTED:
        return
    try:
        state_doc = dashboard_state.copy()
        state_doc["_id"] = "current_state"
        collection.replace_one({"_id": "current_state"}, state_doc, upsert=True)
        logger.info("Saved state to MongoDB successfully")
    except Exception as e:
        logger.error(f"Error saving state to MongoDB: {str(e)}")

def load_state_cache():
    global dashboard_state
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, 'r', encoding='utf-8') as f:
                data = json.load(f)
                dashboard_state.update(data)
                logger.info("Loaded dashboard state cache successfully")
        except Exception as e:
            logger.error(f"Error loading state cache: {str(e)}")

def save_state_cache():
    try:
        with open(CACHE_FILE, 'w', encoding='utf-8') as f:
            json.dump(dashboard_state, f, indent=4)
    except Exception as e:
        logger.error(f"Error saving state cache: {str(e)}")

# Load state cache immediately
load_state_cache()

# Initialize MongoDB connection
initialize_mongodb()

# Symbols to watch - Updated with 'm' suffix for Exness
WATCHLIST_SYMBOLS = ["EURUSDm", "GBPUSDm", "USDJPYm", "XAUUSDm", "BTCUSDm"]

def initialize_mt5():
    """Initialize MT5 connection with proper error handling"""
    global mt5_connected
    if not MT5_AVAILABLE:
        mt5_connected = False
        return False
    
    try:
        # Check if MT5 is already initialized
        if mt5.terminal_info() is not None:
            mt5_connected = True
            logger.info("MT5 already initialized")
            return True
            
        # Initialize MT5
        if not mt5.initialize():
            error = mt5.last_error()
            logger.error(f"Failed to initialize MT5: {error}")
            mt5_connected = False
            return False
            
        # Verify connection
        if mt5.terminal_info() is None:
            logger.error("MT5 initialized but terminal info is None")
            mt5_connected = False
            return False
            
        mt5_connected = True
        logger.info("MT5 initialized successfully")
        return True
        
    except Exception as e:
        logger.error(f"Error initializing MT5: {str(e)}")
        mt5_connected = False
        return False

def ensure_mt5_connection():
    """Ensure MT5 is connected, attempt reconnection if needed"""
    global mt5_connected, last_connection_attempt
    if not MT5_AVAILABLE:
        mt5_connected = False
        return False
    
    with connection_lock:
        current_time = time.time()
        
        # If connected, verify it's still working
        if mt5_connected:
            try:
                if mt5.terminal_info() is not None:
                    return True
                else:
                    logger.warning("MT5 connection lost, attempting reconnect...")
                    mt5_connected = False
            except Exception as e:
                logger.warning(f"MT5 connection check failed: {str(e)}")
                mt5_connected = False
                
        # Attempt reconnection if not connected and enough time has passed
        if not mt5_connected and (current_time - last_connection_attempt > 5):
            last_connection_attempt = current_time
            return initialize_mt5()
            
        return mt5_connected

def get_account_info():
    """Get account information from MT5"""
    if not ensure_mt5_connection():
        return None
        
    try:
        account_info = mt5.account_info()
        if account_info is None:
            logger.error("Failed to get account info")
            return None
            
        return {
            'account_id': account_info.login,
            'account_name': account_info.name,
            'server': account_info.server,
            'balance': round(account_info.balance, 2),
            'equity': round(account_info.equity, 2),
            'profit': round(account_info.profit, 2),
            'margin': round(account_info.margin, 2),
            'free_margin': round(account_info.margin_free, 2),
            'margin_level': round(account_info.margin_level, 2) if account_info.margin_level is not None else 0,
            'currency': account_info.currency,
            'leverage': account_info.leverage
        }
    except Exception as e:
        logger.error(f"Error getting account info: {str(e)}")
        return None

def get_positions():
    """Get all open positions from MT5"""
    if not ensure_mt5_connection():
        return []
        
    try:
        positions = mt5.positions_get()
        if positions is None:
            logger.error("Failed to get positions")
            return []
            
        result = []
        for pos in positions:
            result.append({
                'ticket': pos.ticket,
                'symbol': pos.symbol,
                'type': 'buy' if pos.type == 0 else 'sell',
                'volume': pos.volume,
                'open_price': round(pos.price_open, 5),
                'current_price': round(pos.price_current, 5),
                'stop_loss': round(pos.sl, 5) if pos.sl is not None else 0,
                'take_profit': round(pos.tp, 5) if pos.tp is not None else 0,
                'profit': round(pos.profit, 2),
                'swap': round(pos.swap, 2),
                'time': pos.time
            })
        return result
    except Exception as e:
        logger.error(f"Error getting positions: {str(e)}")
        return []

def get_history(period='day'):
    """Get recent closed orders history from MT5 for the specified period"""
    if not ensure_mt5_connection():
        return []
        
    try:
        now = datetime.now()
        if period == 'day':
            from_date = datetime(now.year, now.month, now.day)
        elif period == 'week':
            from_date = now - timedelta(days=7)
        elif period == 'month':
            from_date = now - timedelta(days=30)
        elif period == 'current_month':
            from_date = datetime(now.year, now.month, 1)
        else:
            from_date = now - timedelta(days=1)
            
        history = mt5.history_deals_get(from_date, now)
        if history is None:
            logger.error("Failed to get history")
            return []
            
        result = []
        for deal in history:
            # Filter only actual trades with volume > 0 and valid symbols. Type 0 is BUY, Type 1 is SELL
            if deal.type in [0, 1] and deal.volume > 0 and deal.symbol:
                deal_time = datetime.fromtimestamp(deal.time).strftime('%Y-%m-%d %H:%M')
                result.append({
                    'ticket': deal.ticket,
                    'symbol': deal.symbol,
                    'type': 'buy' if deal.type == 0 else 'sell',
                    'volume': deal.volume,
                    'price': round(deal.price, 5),
                    'profit': round(deal.profit, 2),
                    'commission': round(deal.commission, 2),
                    'swap': round(deal.swap, 2),
                    'time': deal_time
                })
        
        return result
    except Exception as e:
        logger.error(f"Error getting history: {str(e)}")
        return []

def get_watchlist():
    """Get current prices for watchlist symbols"""
    if not ensure_mt5_connection():
        return []
        
    try:
        result = []
        for symbol_name in WATCHLIST_SYMBOLS:
            # Try to get symbol info
            symbol_info = mt5.symbol_info(symbol_name)
            
            # If symbol not found, try alternative names
            if symbol_info is None:
                alt_symbols = [
                    symbol_name.replace('m', ''),
                    symbol_name.replace('m', '.m'),
                ]
                for alt in alt_symbols:
                    symbol_info = mt5.symbol_info(alt)
                    if symbol_info:
                        symbol_name = alt
                        break
            
            if symbol_info is None:
                logger.warning(f"Symbol {symbol_name} not found")
                continue
                
            tick = mt5.symbol_info_tick(symbol_name)
            if tick is None:
                logger.warning(f"No tick data for {symbol_name}")
                continue
                
            # Get daily high/low if available
            rates = mt5.copy_rates_from_pos(symbol_name, mt5.TIMEFRAME_D1, 0, 1)
            high = low = tick.bid
            if rates is not None and len(rates) > 0:
                high = rates[0]['high']
                low = rates[0]['low']
                
            result.append({
                'symbol': symbol_name,
                'bid': round(tick.bid, 5),
                'ask': round(tick.ask, 5),
                'spread': round(tick.ask - tick.bid, 5),
                'high': round(high, 5),
                'low': round(low, 5)
            })
        return result
    except Exception as e:
        logger.error(f"Error getting watchlist: {str(e)}")
        return []

def get_statistics():
    """Get trading statistics"""
    try:
        account = get_account_info()
        history = get_history()
        
        if not account:
            return {}
            
        # Calculate statistics
        total_profit = account.get('profit', 0)
        total_equity = account.get('equity', 0)
        
        # Calculate win rate from history
        winning_trades = 0
        total_trades = len(history)
        for deal in history:
            if deal.get('profit', 0) > 0:
                winning_trades += 1
                
        win_rate = (winning_trades / total_trades * 100) if total_trades > 0 else 0
        
        return {
            'total_positions': len(get_positions()),
            'total_profit': total_profit,
            'total_equity': total_equity,
            'total_trades': total_trades,
            'winning_trades': winning_trades,
            'win_rate': round(win_rate, 2),
            'balance': account.get('balance', 0),
            'free_margin': account.get('free_margin', 0),
            'margin_level': account.get('margin_level', 0)
        }
    except Exception as e:
        logger.error(f"Error getting statistics: {str(e)}")
        return {}

def get_dashboard_data():
    """Get all dashboard data in one call"""
    return {
        'account': get_account_info(),
        'positions': get_positions(),
        'history': get_history(),
        'watchlist': get_watchlist(),
        'statistics': get_statistics(),
        'timestamp': datetime.now().isoformat()
    }

# ============================================================
# FLASK WEB SERVER ROUTING
# ============================================================

@app.route('/')
def index():
    """Serves the premium responsive frontend dashboard"""
    try:
        return render_template('index.html')
    except Exception as e:
        logger.error(f"Template rendering exception: {str(e)}")
        return "index.html template file missing from the /templates directory.", 404

@app.route('/api/dashboard')
def api_dashboard():
    """Unified single-call update pipeline for the dashboard framework"""
    connected = mt5_connected
    if not connected and dashboard_state.get("last_update"):
        try:
            last_up = datetime.fromisoformat(dashboard_state["last_update"])
            connected = (datetime.now() - last_up).total_seconds() < 60
        except Exception:
            pass
    return jsonify({
        'connected': connected,
        'data': {
            'account': dashboard_state.get("account", {}),
            'positions': dashboard_state.get("positions", []),
            'history': dashboard_state.get("history", []),
            'watchlist': dashboard_state.get("watchlist", []),
            'statistics': dashboard_state.get("statistics", {}),
            'timestamp': dashboard_state.get("last_update") or datetime.now().isoformat()
        }
    })

@app.route('/api/status')
def api_status():
    if MT5_AVAILABLE:
        return jsonify({'connected': mt5_connected})
    else:
        # For push mode, consider connected if we have received an update within the last 60 seconds
        if dashboard_state.get("last_update"):
            try:
                last_up = datetime.fromisoformat(dashboard_state["last_update"])
                is_active = (datetime.now() - last_up).total_seconds() < 60
                return jsonify({'connected': is_active})
            except Exception:
                pass
        return jsonify({'connected': False})

@app.route('/api/update', methods=['POST'])
def api_update():
    global dashboard_state
    try:
        data = flask.request.get_json(force=True)
        if not data:
            return jsonify({"error": "No data provided"}), 400
            
        dashboard_state["account"] = data.get("account", {})
        dashboard_state["positions"] = data.get("positions", [])
        
        # Merge history deals based on ticket ID to persist all trades
        existing_history = dashboard_state.get("history", [])
        if not isinstance(existing_history, list):
            existing_history = []
        existing_by_ticket = {str(d.get("ticket")): d for d in existing_history if d and d.get("ticket")}
        
        new_deals = data.get("history", [])
        if isinstance(new_deals, list):
            for deal in new_deals:
                if deal and deal.get("ticket"):
                    t_id = str(deal.get("ticket"))
                    existing_by_ticket[t_id] = deal
            
        dashboard_state["history"] = sorted(existing_by_ticket.values(), key=lambda x: x.get("time", ""), reverse=True)
        
        dashboard_state["watchlist"] = data.get("watchlist", [])
        dashboard_state["last_update"] = datetime.now().isoformat()
        
        save_state_cache()
        save_state_to_mongodb()
        
        logger.info(f"Dashboard state updated from EA (Account ID: {dashboard_state['account'].get('account_id')})")
        return jsonify({"success": True})
    except Exception as e:
        logger.error(f"Error in api_update: {str(e)}")
        return jsonify({"error": str(e)}), 500
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "nhoy")

@app.route('/api/admin/login', methods=['POST'])
def api_admin_login():
    try:
        data = flask.request.get_json(force=True)
        password = data.get("password")
        if password == ADMIN_PASSWORD:
            return jsonify({"success": True})
        return jsonify({"error": "Incorrect password"}), 401
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/settings', methods=['GET', 'POST'])
def api_settings():
    global dashboard_state
    if flask.request.method == 'POST':
        try:
            # Check basic password header or payload security
            password = flask.request.headers.get("X-Admin-Password")
            if password != ADMIN_PASSWORD:
                data = flask.request.get_json(force=True)
                password = data.get("password")
                if password != ADMIN_PASSWORD:
                    return jsonify({"error": "Unauthorized"}), 401
            else:
                data = flask.request.get_json(force=True)
            
            settings = data.get("settings", {})
            if "target_usd" in settings:
                dashboard_state["settings"]["target_usd"] = float(settings["target_usd"])
            if "mock_data_enabled" in settings:
                dashboard_state["settings"]["mock_data_enabled"] = bool(settings["mock_data_enabled"])
            if "allowed_accounts" in settings:
                dashboard_state["settings"]["allowed_accounts"] = [int(x) for x in settings["allowed_accounts"]]
            
            save_state_cache()
            save_state_to_mongodb()
            return jsonify({"success": True, "settings": dashboard_state["settings"]})
        except Exception as e:
            return jsonify({"error": str(e)}), 500
    else:
        # GET method
        return jsonify(dashboard_state.get("settings", {
            "target_usd": 2000.0,
            "mock_data_enabled": False,
            "allowed_accounts": [415868928]
        }))

@app.route('/api/account')
def api_account():
    # Return from memory cache if available
    data = dashboard_state.get("account")
    if data and data.get("account_id"):
        return jsonify(data)
        
    if MT5_AVAILABLE and ensure_mt5_connection():
        data = get_account_info()
        if data:
            return jsonify(data)
            
    return jsonify({'error': 'MT5 not connected and no cache data available'}), 503

@app.route('/api/positions')
def api_positions():
    # Return from memory cache
    positions = dashboard_state.get("positions", [])
    if positions:
        return jsonify({'positions': positions})
        
    if MT5_AVAILABLE and ensure_mt5_connection():
        return jsonify({'positions': get_positions()})
        
    return jsonify({'positions': []})

@app.route('/api/history')
def api_history():
    period = flask.request.args.get('period', 'day')
    if period == 'day' and dashboard_state.get("history"):
        return jsonify({'orders': dashboard_state["history"]})
        
    if MT5_AVAILABLE and ensure_mt5_connection():
        return jsonify({'orders': get_history(period)})
        
    # Fallback to push/cache data
    orders = dashboard_state.get("history", [])
    
    # Filter by period
    now = datetime.now()
    if period == 'day':
        cutoff = datetime(now.year, now.month, now.day)
    elif period == 'week':
        cutoff = now - timedelta(days=7)
    elif period == 'month':
        cutoff = now - timedelta(days=30)
    elif period == 'current_month':
        cutoff = datetime(now.year, now.month, 1)
    else:
        cutoff = now - timedelta(days=1)
        
    filtered = []
    for o in orders:
        try:
            o_time = datetime.strptime(o['time'], '%Y-%m-%d %H:%M')
            if o_time >= cutoff:
                filtered.append(o)
        except Exception:
            filtered.append(o)
            
    return jsonify({'orders': filtered})

@app.route('/api/watchlist')
def api_watchlist():
    symbols = dashboard_state.get("watchlist", [])
    if symbols:
        return jsonify({'symbols': symbols})
        
    if MT5_AVAILABLE and ensure_mt5_connection():
        return jsonify({'symbols': get_watchlist()})
        
    return jsonify({'symbols': []})

@app.route('/api/statistics')
def api_statistics():
    stats = dashboard_state.get("statistics")
    if stats:
        return jsonify({'connected': mt5_connected, 'data': stats})
        
    if MT5_AVAILABLE and ensure_mt5_connection():
        return jsonify({'connected': True, 'data': get_statistics()})
    return jsonify({'connected': False, 'error': 'Statistics not supported in push mode'})

@app.route('/api/news')
def api_news():
    news = dashboard_state.get("news", [])
    return jsonify({"news": news})

def get_fallback_mock_news():
    from datetime import datetime, timedelta
    now = datetime.now()
    return [
        {
            "title": "Core Retail Sales m/m",
            "country": "USD",
            "date": (now + timedelta(hours=2)).isoformat(),
            "impact": "High",
            "forecast": "0.1%",
            "previous": "0.2%"
        },
        {
            "title": "CPI m/m",
            "country": "USD",
            "date": (now + timedelta(hours=5)).isoformat(),
            "impact": "High",
            "forecast": "0.2%",
            "previous": "0.0%"
        },
        {
            "title": "Monetary Policy Summary",
            "country": "GBP",
            "date": (now + timedelta(hours=9)).isoformat(),
            "impact": "High",
            "forecast": "",
            "previous": ""
        },
        {
            "title": "Flash Manufacturing PMI",
            "country": "EUR",
            "date": (now + timedelta(hours=24)).isoformat(),
            "impact": "Medium",
            "forecast": "45.8",
            "previous": "45.6"
        },
        {
            "title": "Unemployment Rate",
            "country": "USD",
            "date": (now + timedelta(hours=28)).isoformat(),
            "impact": "High",
            "forecast": "4.0%",
            "previous": "3.9%"
        }
    ]

def fetch_forex_factory_news():
    import urllib.request
    import urllib.error
    url = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"
    req = urllib.request.Request(
        url, 
        headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status == 200:
                data = json.loads(response.read().decode('utf-8'))
                logger.info(f"Successfully fetched {len(data)} news events from Forex Factory")
                return data
    except urllib.error.URLError as e:
        logger.error(f"Error fetching Forex Factory news: {str(e)}")
    except Exception as e:
        logger.error(f"General error in Forex Factory news fetch: {str(e)}")
    return None

def background_mt5_updater():
    global dashboard_state, mt5_connected
    logger.info("Starting background MT5 updater daemon...")
    
    last_db_save_time = time.time()
    last_state_hash = None
    last_news_fetch_time = 0
    
    while True:
        try:
            settings = dashboard_state.get("settings", {})
            mock_enabled = settings.get("mock_data_enabled", False)
            
            # Fetch Forex Factory Economic Calendar news once every hour
            current_time = time.time()
            if current_time - last_news_fetch_time > 3600:
                news = fetch_forex_factory_news()
                if news is not None:
                    dashboard_state["news"] = news
                    last_news_fetch_time = current_time
                else:
                    if not dashboard_state.get("news"):
                        dashboard_state["news"] = get_fallback_mock_news()
                        logger.warning("Forex Factory fetch failed. Seeded cache with fallback mock news.")
                    # Rate-limit aware backoff: retry in 5 minutes (300 seconds) if failed
                    last_news_fetch_time = current_time - 3300
            
            if MT5_AVAILABLE and not mock_enabled:
                connected = ensure_mt5_connection()
                if connected:
                    acc = get_account_info()
                    positions = get_positions()
                    watchlist = get_watchlist()
                    stats = get_statistics()
                    history = get_history('day')
                    
                    if acc is not None:
                        dashboard_state["account"] = acc
                    dashboard_state["positions"] = positions
                    dashboard_state["watchlist"] = watchlist
                    dashboard_state["statistics"] = stats
                    dashboard_state["history"] = history
                    dashboard_state["last_update"] = datetime.now().isoformat()
                    mt5_connected = True
                else:
                    mt5_connected = False
            
            # Throttled MongoDB and Cache file saving (every 10 seconds, or if positions/balance changed)
            if current_time - last_db_save_time > 10:
                state_sig = {
                    "balance": dashboard_state.get("account", {}).get("balance"),
                    "positions_count": len(dashboard_state.get("positions", [])),
                    "watchlist_count": len(dashboard_state.get("watchlist", []))
                }
                state_hash = json.dumps(state_sig, sort_keys=True)
                
                if state_hash != last_state_hash or (current_time - last_db_save_time > 30):
                    save_state_cache()
                    save_state_to_mongodb()
                    last_state_hash = state_hash
                    
                last_db_save_time = current_time
                
        except Exception as e:
            logger.error(f"Error in background MT5 updater: {str(e)}")
            
        time.sleep(1.0)

# Start background thread immediately on module import
t_updater = threading.Thread(target=background_mt5_updater, daemon=True)
t_updater.start()
logger.info("Background MT5 updater thread started")

if __name__ == '__main__':
    # Initialize connection immediately upon thread setup
    initialize_mt5()
    
    port = int(os.environ.get('PORT', 5000))
    # Fire up the engine server
    try:
        from waitress import serve
        logger.info(f"Initializing high-availability Waitress engine on http://localhost:{port}")
        serve(app, host='0.0.0.0', port=port, threads=4)
    except ImportError:
        logger.info("Waitress module uninstalled. Activating standard Flask server architecture")
        app.run(host='0.0.0.0', port=port, debug=False)