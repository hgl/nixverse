package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"sync"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
	"golang.org/x/sync/semaphore"
)

type job struct {
	name         string
	command      string
	latestLine   string
	maxNameWidth int
	nameWidth    int
	status       jobStatus
	err          error
	file         *os.File
}

func (job *job) UnmarshalJSON(data []byte) error {
	var v struct {
		Name    string `json:"name"`
		Command string `json:"command"`
	}
	err := json.Unmarshal(data, &v)
	if err != nil {
		return err
	}
	job.name = v.Name
	job.command = v.Command
	job.nameWidth = ansi.StringWidth(job.name)
	return nil
}

func (job job) String() string {
	switch job.status {
	case jobStatusWaiting:
		return "🕘waiting"
	case jobStatusRunning:
		return job.latestLine
	case jobStatusMetaError:
		return "❌" + job.err.Error()
	case jobStatusRunError:
		return "❌Failed, messages are displayed after the rest are finished."
	case jobStatusSucceeded:
		return "✅Done"
	default:
		panic("unknown job status")
	}
}

type jobStatus int

const (
	jobStatusWaiting jobStatus = iota
	jobStatusRunning
	jobStatusSucceeded
	jobStatusMetaError
	jobStatusRunError
)

func (job job) FilterValue() string { return "" }

type itemDelegate struct{}

func (d itemDelegate) Height() int                             { return 1 }
func (d itemDelegate) Spacing() int                            { return 0 }
func (d itemDelegate) Update(_ tea.Msg, _ *list.Model) tea.Cmd { return nil }
func (d itemDelegate) Render(w io.Writer, m list.Model, index int, listItem list.Item) {
	job := listItem.(*job)
	name := lipgloss.NewStyle().
		Bold(true).
		PaddingRight(job.maxNameWidth - job.nameWidth).
		SetString(job.name).String()

	fmt.Fprintf(w, "%s  %s", name, job)
}

type jobLatestLineMsg struct {
	index int
	text  string
}

type jobFailedMsg struct {
	index int
}

type jobMetaErrorMsg struct {
	index int
	err   error
}

type jobSucceededMsg struct {
	index int
}
type jobsSucceededMsg struct{}

type model struct {
	list       list.Model
	ch         chan tea.Msg
	failedJobs []int
}

var errJobFailed = errors.New("some job failed")

func (m model) nextStatus() tea.Msg {
	return <-m.ch
}

func (m model) Init() tea.Cmd {
	return m.nextStatus
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		height := msg.Height
		numItem := len(m.list.Items())
		if numItem > height {
			m.list.SetShowPagination(true)
		} else {
			height = numItem
		}
		m.list.SetSize(msg.Width, height)
		return m, nil
	case jobLatestLineMsg:
		job := m.list.Items()[msg.index].(*job)
		job.latestLine = msg.text
		job.status = jobStatusRunning
		m.list.SetItem(msg.index, job)
		return m, m.nextStatus
	case jobMetaErrorMsg:
		job := m.list.Items()[msg.index].(*job)
		job.status = jobStatusRunError
		job.err = msg.err
		m.list.SetItem(msg.index, job)
		return m, m.nextStatus
	case jobFailedMsg:
		m.failedJobs = append(m.failedJobs, msg.index)
		job := m.list.Items()[msg.index].(*job)
		job.status = jobStatusRunError
		m.list.SetItem(msg.index, job)
		return m, m.nextStatus
	case jobSucceededMsg:
		job := m.list.Items()[msg.index].(*job)
		job.status = jobStatusSucceeded
		m.list.SetItem(msg.index, job)
		return m, m.nextStatus
	case jobsSucceededMsg:
		return m, tea.Quit
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m model) View() string {
	return m.list.View() + "\n"
}

func run() error {
	numParallelJobs, err := strconv.Atoi(os.Args[1])
	if err != nil {
		return err
	}

	f, err := os.Open(os.Args[2])
	if err != nil {
		return err
	}
	defer f.Close()

	var jobs []*job
	err = json.NewDecoder(f).Decode(&jobs)
	if err != nil {
		return err
	}

	if len(jobs) == 0 {
		return nil
	}

	ctx := context.Background()

	if len(jobs) == 1 {
		cmd := exec.CommandContext(ctx, "bash", "-c", jobs[0].command)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		return cmd.Run()
	}

	items := make([]list.Item, len(jobs))
	cmds := make([]*exec.Cmd, len(jobs))
	maxWidth := 0
	for i, job := range jobs {
		f, err := os.CreateTemp("", "*")
		if err != nil {
			return err
		}
		defer f.Close()
		job.file = f

		items[i] = list.Item(job)

		cmd := exec.CommandContext(ctx, "bash", "-c", job.command)
		cmds[i] = cmd
		defer func() {
			if cmd.Process != nil {
				cmd.Process.Signal(os.Interrupt)
			}
		}()
		if job.nameWidth > maxWidth {
			maxWidth = job.nameWidth
		}
	}

	for _, job := range jobs {
		job.maxNameWidth = maxWidth
	}

	var wg sync.WaitGroup
	wg.Add(len(jobs))
	sem := semaphore.NewWeighted(int64(numParallelJobs))
	ch := make(chan tea.Msg)
	go func() {
		for i, job := range jobs {
			err := sem.Acquire(ctx, 1)
			if err != nil {
				go func() { ch <- jobMetaErrorMsg{i, err} }()
				continue
			}

			cmd := cmds[i]
			pr, pw := io.Pipe()
			cmd.Stdout = pw
			cmd.Stderr = pw
			err = cmd.Start()
			if err != nil {
				go func() { ch <- jobMetaErrorMsg{i, err} }()
				continue
			}
			go func() {
				defer sem.Release(1)
				defer wg.Done()
				err := cmd.Wait()
				if _, ok := err.(*exec.ExitError); ok {
					ch <- jobFailedMsg{i}
					return
				}
				if err != nil {
					ch <- jobMetaErrorMsg{i, err}
					return
				}
				ch <- jobSucceededMsg{i}
			}()
			r := io.TeeReader(pr, job.file)
			scan := bufio.NewScanner(r)
			go func() {
				for scan.Scan() {
					ch <- jobLatestLineMsg{i, scan.Text()}
				}
				err := scan.Err()
				if err != nil {
					ch <- jobMetaErrorMsg{i, err}
				}
			}()
		}
		wg.Wait()
		ch <- jobsSucceededMsg{}
	}()

	l := list.New(items, itemDelegate{}, 0, 5)
	l.KeyMap.CursorDown.SetKeys()
	l.KeyMap.CursorUp.SetKeys()
	l.KeyMap.PrevPage.SetKeys("left", "up", "h", "k", "pgup", "b", "u")
	l.KeyMap.NextPage.SetKeys("right", "down", "l", "j", "pgdown", "f", "d")
	l.Styles.PaginationStyle = l.Styles.PaginationStyle.PaddingLeft(0)
	l.Paginator.ActiveDot = l.Styles.ActivePaginationDot.Foreground(lipgloss.AdaptiveColor{Light: "235", Dark: "255"}).String()
	l.Paginator.InactiveDot = l.Styles.InactivePaginationDot.Foreground(lipgloss.AdaptiveColor{Light: "250", Dark: "242"}).String()
	l.SetShowTitle(false)
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(false)
	l.SetShowPagination(false)
	l.SetShowHelp(false)
	m := model{list: l, ch: ch, failedJobs: make([]int, 0)}
	tm, err := tea.NewProgram(m).Run()
	if err != nil {
		return err
	}
	m = tm.(model)
	for i, jobIndex := range m.failedJobs {
		job := m.list.Items()[jobIndex].(job)
		if i != 0 {
			fmt.Fprintln(os.Stderr, "")
		}
		title := lipgloss.NewStyle().Foreground(lipgloss.Color("160")).
			SetString("### Output of " + job.name)
		fmt.Fprintln(os.Stderr, title)
		_, err := job.file.Seek(0, 0)
		if err != nil {
			return err
		}
		_, err = io.Copy(os.Stderr, job.file)
		if err != nil {
			return err
		}
	}
	if len(m.failedJobs) != 0 {
		return errJobFailed
	}
	return nil
}

func main() {
	err := run()
	if err == errJobFailed {
		os.Exit(1)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
