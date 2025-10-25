# Task: Remove DaisyUI and Optimize Bundle Size

## Category
Performance, Code Quality

## Priority
**MEDIUM** - 300KB+ unnecessary bundle bloat

## Description
DaisyUI is imported but barely used, adding ~300KB to the bundle size. Additionally, there's duplicate JavaScript code (TrendChart and PercentageTrendChart are nearly identical with 400+ lines duplicated). The bundle needs optimization.

## Current State
```css
/* assets/css/app.css */
@plugin "../vendor/daisyui" {
  themes: false;  /* Adding 300KB for nothing! */
}
```

```javascript
// assets/js/charts.js
// TrendChart: 400+ lines
// PercentageTrendChart: 400+ lines (DUPLICATE!)
// Total unnecessary duplication
```

## Proposed Solution

### Step 1: Remove DaisyUI Completely
```bash
# Remove DaisyUI files
rm assets/vendor/daisyui.js
rm assets/vendor/daisyui-theme.js
```

```css
/* assets/css/app.css - UPDATED */
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/live_poll_web";

/* Remove this line:
@plugin "../vendor/daisyui" { themes: false; }
*/

/* Custom Tailwind components to replace DaisyUI */
@layer components {
  .btn {
    @apply inline-flex items-center justify-center px-4 py-2 
           font-medium rounded-lg transition-colors duration-200 
           focus:outline-none focus:ring-2 focus:ring-offset-2;
  }
  
  .btn-primary {
    @apply bg-blue-600 text-white hover:bg-blue-700 
           focus:ring-blue-500 active:bg-blue-800;
  }
  
  .btn-secondary {
    @apply bg-gray-600 text-white hover:bg-gray-700 
           focus:ring-gray-500 active:bg-gray-800;
  }
  
  .btn-danger {
    @apply bg-red-600 text-white hover:bg-red-700 
           focus:ring-red-500 active:bg-red-800;
  }
  
  .btn-success {
    @apply bg-green-600 text-white hover:bg-green-700 
           focus:ring-green-500 active:bg-green-800;
  }
  
  .btn-sm {
    @apply px-3 py-1.5 text-sm;
  }
  
  .btn-lg {
    @apply px-6 py-3 text-lg;
  }
  
  .card {
    @apply bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6;
  }
  
  .input {
    @apply w-full px-3 py-2 border border-gray-300 dark:border-gray-600 
           rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500
           dark:bg-gray-700 dark:text-white;
  }
  
  .label {
    @apply block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1;
  }
  
  .alert {
    @apply p-4 rounded-lg border;
  }
  
  .alert-info {
    @apply bg-blue-50 dark:bg-blue-900/20 text-blue-800 dark:text-blue-200 
           border-blue-200 dark:border-blue-800;
  }
  
  .alert-error {
    @apply bg-red-50 dark:bg-red-900/20 text-red-800 dark:text-red-200 
           border-red-200 dark:border-red-800;
  }
}
```

### Step 2: Consolidate Duplicate JavaScript
```javascript
// assets/js/charts.js - REFACTORED
import * as echarts from 'echarts/core';
import {
  TitleComponent,
  TooltipComponent,
  LegendComponent,
  GridComponent
} from 'echarts/components';
import { PieChart, LineChart, BarChart } from 'echarts/charts';
import { CanvasRenderer } from 'echarts/renderers';

// Register only needed components (tree-shaking)
echarts.use([
  TitleComponent,
  TooltipComponent,
  LegendComponent,
  GridComponent,
  PieChart,
  LineChart,
  BarChart,
  CanvasRenderer
]);

// Base chart class to avoid duplication
class BaseChart {
  constructor(el, type) {
    this.el = el;
    this.type = type;
    this.chart = null;
    this.resizeObserver = null;
  }
  
  mounted() {
    this.initChart();
    this.setupResizeObserver();
    this.handleEvent(`update-${this.type}-chart`, data => this.updateChart(data));
  }
  
  destroyed() {
    this.cleanup();
  }
  
  initChart() {
    const theme = document.documentElement.classList.contains('dark') ? 'dark' : 'light';
    this.chart = echarts.init(this.el, theme);
    this.chart.setOption(this.getBaseOptions());
  }
  
  setupResizeObserver() {
    this.resizeObserver = new ResizeObserver(() => {
      this.chart?.resize();
    });
    this.resizeObserver.observe(this.el);
  }
  
  cleanup() {
    this.resizeObserver?.disconnect();
    this.chart?.dispose();
    this.chart = null;
  }
  
  updateChart(data) {
    if (!this.chart || this.chart.isDisposed()) return;
    
    const option = this.buildChartOption(data);
    this.chart.setOption(option, {
      notMerge: false,
      lazyUpdate: true,
      silent: true
    });
  }
  
  getBaseOptions() {
    // Override in subclasses
    return {};
  }
  
  buildChartOption(data) {
    // Override in subclasses
    return {};
  }
}

// Specific chart implementations
class PieChartHook extends BaseChart {
  constructor(el) {
    super(el, 'pie');
  }
  
  getBaseOptions() {
    return {
      tooltip: {
        trigger: 'item',
        formatter: '{b}: {c} ({d}%)'
      },
      legend: {
        orient: 'vertical',
        left: 'left'
      },
      series: [{
        type: 'pie',
        radius: '50%',
        emphasis: {
          itemStyle: {
            shadowBlur: 10,
            shadowOffsetX: 0,
            shadowColor: 'rgba(0, 0, 0, 0.5)'
          }
        }
      }]
    };
  }
  
  buildChartOption(data) {
    return {
      series: [{
        data: data.map(item => ({
          name: this.escapeHtml(item.name),
          value: item.value
        }))
      }]
    };
  }
  
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
}

// Single trend chart implementation (no duplication!)
class TrendChartHook extends BaseChart {
  constructor(el) {
    super(el, 'trend');
    this.dataType = el.dataset.type || 'votes';  // votes or percentage
  }
  
  getBaseOptions() {
    return {
      tooltip: {
        trigger: 'axis',
        formatter: (params) => this.formatTooltip(params)
      },
      legend: {
        data: [],
        bottom: 0
      },
      grid: {
        left: '3%',
        right: '4%',
        bottom: '10%',
        containLabel: true
      },
      xAxis: {
        type: 'time',
        boundaryGap: false
      },
      yAxis: {
        type: 'value',
        max: this.dataType === 'percentage' ? 100 : null,
        axisLabel: {
          formatter: this.dataType === 'percentage' ? '{value}%' : '{value}'
        }
      }
    };
  }
  
  buildChartOption(data) {
    if (!data || !data.trends) return {};
    
    const series = data.languages.map(lang => ({
      name: this.escapeHtml(lang),
      type: 'line',
      smooth: true,
      data: data.trends.map(point => [
        point.time,
        this.dataType === 'percentage' 
          ? point.percentages[lang] || 0
          : point.votes[lang] || 0
      ])
    }));
    
    return {
      legend: { data: data.languages },
      series
    };
  }
  
  formatTooltip(params) {
    const time = new Date(params[0].axisValue).toLocaleTimeString();
    const suffix = this.dataType === 'percentage' ? '%' : ' votes';
    
    let tooltip = `<strong>${time}</strong><br/>`;
    params.forEach(param => {
      const name = this.escapeHtml(param.seriesName);
      tooltip += `${param.marker} ${name}: ${param.value[1]}${suffix}<br/>`;
    });
    
    return tooltip;
  }
  
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
}

// Export hooks
export const ChartHooks = {
  PieChart: {
    mounted() { this.chart = new PieChartHook(this.el); this.chart.mounted(); },
    destroyed() { this.chart?.destroyed(); }
  },
  TrendChart: {
    mounted() { this.chart = new TrendChartHook(this.el); this.chart.mounted(); },
    destroyed() { this.chart?.destroyed(); }
  },
  // Backward compatibility alias
  PercentageTrendChart: {
    mounted() { 
      this.el.dataset.type = 'percentage';
      this.chart = new TrendChartHook(this.el); 
      this.chart.mounted(); 
    },
    destroyed() { this.chart?.destroyed(); }
  }
};
```

### Step 3: Optimize ECharts Bundle
```json
// assets/package.json
{
  "dependencies": {
    "echarts": "^5.5.1"
  },
  "sideEffects": false,
  "scripts": {
    "analyze": "webpack-bundle-analyzer stats.json"
  }
}
```

```javascript
// assets/webpack.config.js
module.exports = {
  optimization: {
    usedExports: true,  // Tree shaking
    sideEffects: false,
    splitChunks: {
      chunks: 'all',
      cacheGroups: {
        echarts: {
          test: /[\\/]node_modules[\\/]echarts/,
          name: 'echarts',
          priority: 10
        }
      }
    }
  }
};
```

### Step 4: Remove Unused Vendor Files
```bash
# Clean up vendor directory
rm assets/vendor/heroicons.js  # Use <.icon> component instead
rm assets/vendor/topbar.js     # If not used

# Keep only essential vendor files
ls assets/vendor/
# Should only have files actually used
```

### Step 5: Update Templates to Use Custom Classes
```heex
<!-- Replace DaisyUI classes with custom Tailwind -->
<!-- Before -->
<button class="btn btn-primary btn-sm">Vote</button>

<!-- After (same classes, custom implementation) -->
<button class="btn btn-primary btn-sm">Vote</button>

<!-- Or use Phoenix components -->
<.button class="btn-sm">Vote</.button>
```

## Requirements
1. ✅ Remove DaisyUI completely (300KB savings)
2. ✅ Consolidate duplicate JavaScript (400+ lines removed)
3. ✅ Implement custom Tailwind components
4. ✅ Optimize ECharts bundle with tree-shaking
5. ✅ Remove unused vendor files
6. ✅ Maintain visual consistency
7. ✅ Reduce total bundle size by 50%+

## Definition of Done
1. **Bundle Optimization**
   - [ ] DaisyUI removed from project
   - [ ] JavaScript duplication eliminated
   - [ ] Tree-shaking configured
   - [ ] Vendor files cleaned up

2. **Visual Consistency**
   - [ ] All UI elements look the same or better
   - [ ] Dark mode still works
   - [ ] Responsive design maintained

3. **Performance Metrics**
   ```bash
   # Measure bundle size
   npm run build
   ls -lh priv/static/assets/
   
   # Before: ~800KB total
   # After: <400KB total (50% reduction)
   ```

4. **Quality Checks**
   - [ ] No console errors
   - [ ] Charts still update properly
   - [ ] All functionality preserved
   - [ ] Lighthouse score improved

## Branch Name
`fix/remove-daisyui-optimize-bundle`

## Dependencies
None - Can be done independently

## Estimated Complexity
**M (Medium)** - 3-4 hours

## Testing Instructions
1. Remove DaisyUI imports
2. Add custom Tailwind components
3. Test all UI elements look correct
4. Consolidate JavaScript files
5. Build assets: `mix assets.deploy`
6. Check bundle sizes in priv/static/assets/
7. Verify charts still work
8. Test dark mode toggle
9. Run Lighthouse audit

## Bundle Size Analysis
### Before
- app.css: ~400KB (DaisyUI included)
- app.js: ~450KB (duplicate code)
- Total: ~850KB

### After (Expected)
- app.css: ~100KB (just Tailwind)
- app.js: ~250KB (consolidated)
- Total: ~350KB (59% reduction!)

## Notes
- Keep the same class names for easy migration
- Custom components are more maintainable
- Tree-shaking requires proper imports
- Consider lazy loading charts if not immediately visible
- May want to add PurgeCSS for further optimization
