/* 16-bit Accumulator based VM designed using a LFSR instead of a normal
 * Program Counter, See <https://github.com/howerj/lfsr>  */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>

#define SZ (0x2000)
#define POLY (0xB8)
#define VHDL_COMPATIBLE_DEBUG (1)

typedef struct {
	uint16_t m[SZ], pc, a, first;
	int (*get)(void *in);
	int (*put)(void *out, int ch);
	void *in, *out;
	FILE *debug;
} vm_t;

static inline uint8_t lfsr(uint8_t n, uint8_t polynomial_mask) {
	const int feedback = n & 1;
	n >>= 1;
	return feedback ? n ^ polynomial_mask : n;
}

static inline uint16_t load(vm_t *v, uint16_t addr) {
	assert(v); /* more peripherals could be added if needed */
	return addr & 0x8000 ? v->get(v->in) : v->m[addr % SZ];
}

static inline void store(vm_t *v, uint16_t addr, uint16_t val, long cycles) {
	assert(v);
	if (addr & 0x8000) {
		if (!v->first) { /* Useful to know when simulating the VHDL test-bench */
			v->first = 1;
			if (v->debug)
				(void)fprintf(v->debug, "Cycles until first output: %ld\n", cycles);
		}
		(void)v->put(v->out, val);
	} else {
		v->m[addr % SZ] = val;
	}
}

static int run(vm_t *v) {
	assert(v);
	uint16_t pc = v->pc, a = v->pc, *m = v->m; /* load machine state */
	static const char *names[] = { "and", "xor", "lsl1", "lsr1", "load", "store", "jmp", "jmpz", };
	for (long cycles = 0;;cycles++) { /* An `ADD` instruction things up greatly, `OR` not so much */
		const uint16_t ins = m[pc % SZ];
		const uint16_t imm = ins & 0xFFF;
		const uint16_t alu = (ins >> 12) & 0x7;
		const uint8_t _pc = lfsr(pc, POLY);
		const uint16_t arg = ins & 0x8000 ? load(v, imm) : imm;
		if (VHDL_COMPATIBLE_DEBUG) {
			if (v->debug && fprintf(v->debug, "%d: a_%s %d\n", (unsigned)pc, names[alu], (unsigned)a) < 0) return -1;
		} else { /* The VHDL test bench outputs the same format to stdio if a debugging generic is enabled */
			if (v->debug && fprintf(v->debug, "%04x: %c %5s %04X %04X\t%ld\n", 
					(unsigned)pc, ins & 0x8000 ? 'i' : ' ', names[alu], (unsigned)ins, (unsigned)a, cycles) < 0) return -1;
		}
		switch (alu) {
		case 0: a &= arg; pc = _pc; break;
		case 1: a ^= arg; pc = _pc; break;
		case 2: a <<= 1; pc = _pc; break;
		case 3: a >>= 1; pc = _pc; break;
		case 4: a = load(v, arg); pc = _pc; break;
		case 5: store(v, arg, a, cycles); pc = _pc; break;
		case 6: if (pc == arg) goto end; pc = arg; break; /* `goto end` for testing only */
		case 7: pc = _pc; if (!a) pc = arg; break;
		}
	}
end:
	v->pc = pc; /* save machine state */
	v->a = a;
	return 0;
}

static int put(void *out, int ch) { 
	ch = fputc(ch, (FILE*)out); 
	return fflush((FILE*)out) < 0 ? -1 : ch; 
}

static int get(void *in) { 
	return fgetc((FILE*)in); 
}

static int option(const char *opt) { /* very lazy options */
	char *r = getenv(opt);
	if (!r) return 0;
	return atoi(r); /* could do case insensitive check for "yes"/"on" = 1, and "no"/"off" = 0 as well */
}

int main(int argc, char **argv) {
	vm_t vm = { .pc = 0, .put = put, .get = get, .in = stdin, .out = stdout, .debug = option("DEBUG") ? stderr : NULL, };
	if (argc < 2) {
		(void)fprintf(stderr, "Usage: %s prog.hex\n", argv[0]);
		return 1;
	}
	FILE *prog = fopen(argv[1], "rb");
	if (!prog) {
		(void)fprintf(stderr, "Unable to open file `%s` for reading\n", argv[1]);
		return 2;
	}
	for (size_t i = 0; i < SZ; i++) {
		unsigned long d = 0;
		if (fscanf(prog, "%lx,", &d) != 1) /* optional comma */
			break;
		vm.m[i] = d;
	}
	if (fclose(prog) < 0) return 3;
	return run(&vm) < 0;
}
