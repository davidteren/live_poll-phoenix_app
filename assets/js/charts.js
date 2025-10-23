import * as echarts from 'echarts';

// Language color mapping
const languageColors = {
  'Elixir': '#9b59b6',
  'Python': '#3498db',
  'JavaScript': '#f1c40f',
  'Ruby': '#e74c3c',
  'Go': '#1abc9c',
  'Rust': '#e67e22',
  'TypeScript': '#3498db',
  'Swift': '#ff6b9d',
  'Kotlin': '#9b59b6',
  'PHP': '#2ecc71',
  'Java': '#f39c12',
  'C#': '#8e44ad',
  'C++': '#16a085',
  'Dart': '#34495e',
  'Scala': '#c0392b',
  'Haskell': '#d35400',
  'Clojure': '#27ae60',
  'F#': '#2980b9'
};

const languageColorsDark = {
  'Elixir': '#b19cd9',
  'Python': '#5dade2',
  'JavaScript': '#f4d03f',
  'Ruby': '#ec7063',
  'Go': '#48c9b0',
  'Rust': '#eb984e',
  'TypeScript': '#5dade2',
  'Swift': '#ff85b3',
  'Kotlin': '#b19cd9',
  'PHP': '#58d68d',
  'Java': '#f5b041',
  'C#': '#a569bd',
  'C++': '#45b39d',
  'Dart': '#5d6d7e',
  'Scala': '#cd6155',
  'Haskell': '#dc7633',
  'Clojure': '#52be80',
  'F#': '#5499c7'
};

// Get color based on theme
function getLanguageColor(language) {
  const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
  const colors = isDark ? languageColorsDark : languageColors;
  return colors[language] || '#999999';
}

// Pie Chart Hook
export const PieChart = {
  mounted() {
    this.chart = echarts.init(this.el);
    this.updateChart();

    // Listen for theme changes
    this.observer = new MutationObserver(() => {
      if (this.chart && !this.chart.isDisposed()) {
        this.updateChart();
      }
    });
    this.observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme']
    });

    // Handle window resize
    this.resizeHandler = () => {
      if (this.chart && !this.chart.isDisposed()) {
        this.chart.resize();
      }
    };
    window.addEventListener('resize', this.resizeHandler);

    // Listen for data updates from LiveView
    this.handleEvent('update-pie-chart', ({data}) => {
      this.el.dataset.chartData = JSON.stringify(data);
      this.updateChart();
    });
  },

  updated() {
    // With phx-update="ignore", this won't be called
    // Updates come through handleEvent instead
  },

  updateChart() {
    const data = JSON.parse(this.el.dataset.chartData || '[]');
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    
    const option = {
      backgroundColor: 'transparent',
      tooltip: {
        trigger: 'item',
        formatter: '{b}: {c} votes ({d}%)',
        backgroundColor: isDark ? 'rgba(0, 0, 0, 0.8)' : 'rgba(255, 255, 255, 0.9)',
        borderColor: isDark ? '#444' : '#ddd',
        textStyle: {
          color: isDark ? '#fff' : '#333'
        }
      },
      legend: {
        show: false
      },
      series: [
        {
          name: 'Votes',
          type: 'pie',
          radius: ['40%', '70%'],
          avoidLabelOverlap: false,
          itemStyle: {
            borderRadius: 8,
            borderColor: isDark ? '#1a1a1a' : '#fff',
            borderWidth: 2
          },
          label: {
            show: false
          },
          emphasis: {
            label: {
              show: true,
              fontSize: 16,
              fontWeight: 'bold'
            },
            itemStyle: {
              shadowBlur: 10,
              shadowOffsetX: 0,
              shadowColor: 'rgba(0, 0, 0, 0.5)'
            }
          },
          labelLine: {
            show: false
          },
          data: data.map(item => ({
            value: item.votes,
            name: item.name,
            itemStyle: {
              color: getLanguageColor(item.name)
            }
          }))
        }
      ]
    };

    this.chart.setOption(option);
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
    if (this.resizeHandler) {
      window.removeEventListener('resize', this.resizeHandler);
    }
    if (this.chart && !this.chart.isDisposed()) {
      this.chart.dispose();
    }
  }
};

// Trend Line Chart Hook
export const TrendChart = {
  mounted() {
    this.chart = echarts.init(this.el);
    this.zoomState = null; // Track zoom state
    this.updateChart();

    // Listen for theme changes
    this.observer = new MutationObserver(() => {
      if (this.chart && !this.chart.isDisposed()) {
        this.updateChart();
      }
    });
    this.observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme']
    });

    // Handle window resize
    this.resizeHandler = () => {
      if (this.chart && !this.chart.isDisposed()) {
        this.chart.resize();
      }
    };
    window.addEventListener('resize', this.resizeHandler);

    // Listen for dataZoom events to save zoom state
    this.chart.on('dataZoom', (params) => {
      const option = this.chart.getOption();
      if (option.dataZoom && option.dataZoom.length > 0) {
        this.zoomState = {
          start: option.dataZoom[0].start,
          end: option.dataZoom[0].end
        };
      }
    });

    // Listen for data updates from LiveView
    this.handleEvent('update-trend-chart', ({trendData, languages}) => {
      this.el.dataset.trendData = JSON.stringify(trendData);
      this.el.dataset.languages = JSON.stringify(languages);
      this.updateChart();
    });
  },

  updated() {
    // With phx-update="ignore", this won't be called
    // Updates come through handleEvent instead
  },

  updateChart() {
    const trendData = JSON.parse(this.el.dataset.trendData || '[]');
    const languages = JSON.parse(this.el.dataset.languages || '[]');
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';

    if (trendData.length < 2) {
      // Show "collecting data" message
      const option = {
        backgroundColor: 'transparent',
        title: {
          text: 'Collecting trend data...',
          left: 'center',
          top: 'middle',
          textStyle: {
            color: isDark ? '#999' : '#666',
            fontSize: 14
          }
        }
      };
      this.chart.setOption(option);
      return;
    }

    // Data is already in chronological order (oldest to newest) from the database
    // Extract timestamps for x-axis
    const timestamps = trendData.map(snapshot => {
      const date = new Date(snapshot.timestamp);
      return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    });

    // Create series for each language
    const series = languages.map(language => ({
      name: language,
      type: 'line',
      smooth: true,
      symbol: 'circle',
      symbolSize: 6,
      lineStyle: {
        width: 2,
        color: getLanguageColor(language)
      },
      itemStyle: {
        color: getLanguageColor(language)
      },
      emphasis: {
        focus: 'series'
      },
      data: trendData.map(snapshot =>
        snapshot.percentages[language] || 0
      )
    }));

    const option = {
      backgroundColor: 'transparent',
      tooltip: {
        trigger: 'axis',
        backgroundColor: isDark ? 'rgba(0, 0, 0, 0.8)' : 'rgba(255, 255, 255, 0.9)',
        borderColor: isDark ? '#444' : '#ddd',
        textStyle: {
          color: isDark ? '#fff' : '#333'
        },
        formatter: function(params) {
          let result = `<strong>${params[0].axisValue}</strong><br/>`;
          params.forEach(param => {
            result += `<span style="display:inline-block;width:10px;height:10px;border-radius:50%;background-color:${param.color};margin-right:5px;"></span>`;
            result += `${param.seriesName}: ${param.value.toFixed(1)}%<br/>`;
          });
          return result;
        }
      },
      legend: {
        data: languages,
        textStyle: {
          color: isDark ? '#ccc' : '#666'
        },
        top: 10
      },
      grid: {
        left: '3%',
        right: '4%',
        bottom: '20%',
        top: '15%',
        containLabel: true
      },
      dataZoom: [
        {
          type: 'slider',
          show: true,
          xAxisIndex: [0],
          start: this.zoomState ? this.zoomState.start : 0,
          end: this.zoomState ? this.zoomState.end : 100,
          height: 30,
          bottom: 10,
          borderColor: isDark ? '#444' : '#ddd',
          fillerColor: isDark ? 'rgba(255, 255, 255, 0.1)' : 'rgba(0, 0, 0, 0.1)',
          handleStyle: {
            color: isDark ? '#666' : '#aaa'
          },
          textStyle: {
            color: isDark ? '#999' : '#666'
          }
        },
        {
          type: 'inside',
          xAxisIndex: [0],
          start: this.zoomState ? this.zoomState.start : 0,
          end: this.zoomState ? this.zoomState.end : 100
        }
      ],
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: timestamps,
        axisLine: {
          lineStyle: {
            color: isDark ? '#444' : '#ddd'
          }
        },
        axisLabel: {
          color: isDark ? '#999' : '#666',
          rotate: 45
        }
      },
      yAxis: {
        type: 'value',
        name: 'Percentage (%)',
        nameTextStyle: {
          color: isDark ? '#999' : '#666'
        },
        axisLine: {
          lineStyle: {
            color: isDark ? '#444' : '#ddd'
          }
        },
        axisLabel: {
          color: isDark ? '#999' : '#666',
          formatter: '{value}%'
        },
        splitLine: {
          lineStyle: {
            color: isDark ? '#333' : '#eee'
          }
        }
      },
      series: series
    };

    this.chart.setOption(option);
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
    if (this.resizeHandler) {
      window.removeEventListener('resize', this.resizeHandler);
    }
    if (this.chart && !this.chart.isDisposed()) {
      this.chart.dispose();
    }
  }
};

