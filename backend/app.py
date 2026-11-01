from flask import Flask, jsonify
import psutil

app = Flask(__name__, template_folder="../frontend", static_folder="../frontend")

@app.route('/')
def index():
    return app.send_static_file('index.html')

@app.route('/api/stats')
def stats():
    cpu = psutil.cpu_percent(interval=1)
    ram = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    return jsonify({
        "cpu": cpu,
        "ram_used": round(ram.used / (1024**2), 2),
        "ram_total": round(ram.total / (1024**2), 2),
        "ram_percent": ram.percent,
        "disk_percent": disk.percent
    })

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8989)
